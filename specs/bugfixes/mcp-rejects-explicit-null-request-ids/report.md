# Bugfix Report: MCP Rejects Explicit Null Request IDs

**Date:** 2026-08-02
**Status:** Fixed
**Transit ticket:** T-1863

## Description of the Issue

Transit advertises MCP protocol `2025-03-26`, which requires a JSON-RPC request ID to be a string or integer when present; an explicit `"id": null` is invalid. Transit accepted an explicit null ID as a normal request because its decoder correctly distinguished ID presence, but the handler did not reject the present-but-null state.

**Reproduction steps:**
1. Enable Transit's MCP server.
2. POST `{ "jsonrpc": "2.0", "id": null, "method": "ping" }` to `/mcp`.
3. Before the fix, observe a successful ping response with `id: null` instead of JSON-RPC `-32600 Invalid Request`.

**Impact:** MCP clients sending malformed request envelopes received a positive acknowledgement. The same protocol defect affected single requests and batch members, while notification requests with an omitted ID had to continue executing without a response.

## Investigation Summary

The request model, handler, HTTP route, batch dispatcher, existing T-847 tests, T-847 history, MCP notes, and decode-classification regressions were inspected.

- **Symptoms examined:** Explicit null IDs reached method dispatch and returned successful results; omitted IDs were intentionally suppressed; string and integer IDs worked; batches preserved invalid members and response arrays.
- **Code inspected:** `MCPTypes.swift` (`JSONRPCRequest` presence tracking and response encoding), `MCPToolHandler.swift` (`handle` notification suppression), `MCPServer.swift` (single and batch routing), `MCPServerDecodeTypes.swift`, `MCPNullIdTests.swift`, and `MCPServerBatchRequestTests.swift`.
- **Hypotheses tested:** The decoder losing ID presence was ruled out: `container.contains(.id)` already sets `isNotification` correctly. Batch handling was also ruled out as the primary cause: it delegates request members to the same handler and preserves null-ID error envelopes. T-847's generic JSON-RPC expectation that explicit null should receive a response was obsolete for this MCP endpoint because MCP 2025-03-26 forbids null request IDs.

## Discovered Root Cause

`JSONRPCRequest` represents an explicit null ID as `id == nil` plus `isNotification == false`, which is sufficient to preserve presence. `MCPToolHandler.handle` only checked `request.id` indirectly through the final notification suppression and therefore dispatched the present-but-null request as a normal method call.

**Defect type:** Missing protocol validation at the handler boundary.

**Why it occurred:** T-847 intentionally fixed the ambiguity between omitted IDs and explicit null IDs according to generic JSON-RPC semantics. The later MCP protocol revision is stricter, but no MCP-specific validation was added to the now-preserved explicit-null state, and the T-847 regressions encoded the old expectation as successful behavior.

**Contributing factors:** The response encoder correctly emits a null `id` for error envelopes, and batch handling already has the required per-member response structure, so the defect was easy to miss when inspecting only transport serialization.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` - Reject the presence-aware `id == nil && !isNotification` state with JSON-RPC `-32600 Invalid Request` and a null response ID before method dispatch. Omitted-ID notifications still execute and return no response; string and integer IDs are unchanged.
- `Transit/Transit/MCP/MCPTypes.swift` - Clarify that decoding preserves ID presence for MCP-layer validation rather than treating explicit null as a valid request ID.
- `Transit/TransitTests/MCPNullIdTests.swift` - Replace obsolete T-847 success expectations with focused presence, handler, valid-ID, notification, error-code, and response-envelope regressions.
- `Transit/TransitTests/MCPServerBatchRequestTests.swift` - Verify single-request and batch HTTP behavior, including per-member null-ID errors and unchanged string/integer responses.
- `docs/agent-notes/mcp-server.md` - Replace the stale T-847 gotcha with the current presence-aware MCP validation rule.
- `CHANGELOG.md` - Record the protocol correction under Unreleased fixes.

**Approach rationale:** The decoder already preserves the only information needed to distinguish an omitted ID from explicit null, and the handler is the existing JSON-RPC protocol-validation boundary for other request-shape rules. Validating there avoids changing the batch decoder's per-member preservation behavior and keeps the existing `JSONRPCResponse` encoder responsible for the required `id: null` error envelope.

**Alternatives considered:**
- Treat explicit null as a notification - rejected because it would silently discard an invalid request and violate MCP's request-ID rule.
- Remove the `isNotification` flag or make the decoder throw for explicit null - rejected because omitted-ID notifications need the presence bit, and the handler already centralizes JSON-RPC/MCP request validation while batch decoding must preserve members for per-member errors.
- Return a successful response with `id: null` as T-847 required - rejected because that generic JSON-RPC behavior conflicts with the MCP 2025-03-26 contract advertised by Transit.

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPNullIdTests.swift`
- `Transit/TransitTests/MCPServerBatchRequestTests.swift`

**Tests:**
- `decodingPreservesOmittedIdAndExplicitNullPresence`
- `handlerRejectsExplicitNullIdAsInvalidRequest`
- `invalidNullIdResponseEncodesErrorWithNullId`
- `handlerOmitsResponseForMissingId`
- `handlerReturnsResponsesForStringAndIntegerIds`
- `singleExplicitNullIdReturnsInvalidRequestWithNullId`
- `batchExplicitNullIdIsInvalidWhileStringAndIntegerIdsRemainValid`

**What they verify:** Presence-aware decoding distinguishes omitted IDs from explicit null IDs; explicit null is rejected with `-32600` and an explicitly encoded JSON null response ID; notifications remain response-free; string and integer IDs remain successful; and the same semantics hold for HTTP single requests and JSON-RPC batches.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Reject explicit null request IDs as invalid MCP requests. |
| `Transit/Transit/MCP/MCPTypes.swift` | Document presence-aware ID decoding. |
| `Transit/TransitTests/MCPNullIdTests.swift` | Replace obsolete T-847 expectations and add focused protocol regressions. |
| `Transit/TransitTests/MCPServerBatchRequestTests.swift` | Add single-route and batch-level null-ID response regressions. |
| `docs/agent-notes/mcp-server.md` | Document the current MCP request-ID contract and T-847 supersession. |
| `specs/bugfixes/mcp-rejects-explicit-null-request-ids/report.md` | Investigation and resolution record. |
| `CHANGELOG.md` | Record the MCP protocol correction. |

## Verification

**Automated:**
- [x] Focused regression suites pass: `MCPNullIdTests` and `MCPServerBatchRequestTests` via macOS `xcodebuild test`.
- [x] Full macOS unit suite passes: `make test-quick`.
- [x] Linters/validators pass: `make lint` (including the model-container ownership guard).
- [x] macOS build passes: `make build-macos`.
- [~] `make test` completed after a warmed-cache retry with 1,198 passed and 3 pre-existing UI failures (`testClearAll`, `testEditViewPreservesTaskMilestone`, and `testDataMaintenanceGoldenPath`); none exercise MCP request handling. The first attempt timed out during initial iOS dependency compilation.
- [~] `make test-ui` completed with 18 passed and the same 3 unrelated UI failures. Xcode also emitted repeated `DebuggerLLDB.DebuggerVersionStore.StoreError` warnings during the run.

**Manual verification:**
- [x] Compared single, notification, valid-ID, and batch response envelopes against the MCP 2025-03-26 request-ID rule.
- [x] Confirmed the invalid response envelope retains an explicit `id: null`, while notification-only batches remain HTTP 202 with no body.

## Prevention

- Keep protocol-version-specific validation separate from generic JSON-RPC decoding assumptions.
- Preserve explicit field presence in decoders whenever omitted and null have different protocol meanings.
- Retain route-level single and batch regressions for every request-envelope rule.
- When a protocol revision supersedes an older ticket's behavior, update both the regression expectations and the related implementation notes.

## Related

- Transit ticket T-1863
- Supersedes the generic JSON-RPC expectation implemented by T-847 (PR #121).
- MCP 2025-03-26 basic protocol: https://modelcontextprotocol.io/specification/2025-03-26/basic/
