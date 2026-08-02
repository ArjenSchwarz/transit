# Bugfix Report: MCP Rejects Explicit Null Request IDs

**Date:** 2026-08-02
**Status:** In Progress
**Transit ticket:** T-1863

## Description of the Issue

Transit advertises MCP protocol `2025-03-26`, which requires a JSON-RPC request ID to be a string or integer when present; an explicit `"id": null` is invalid. Transit currently accepts an explicit null ID as a normal request because its decoder correctly distinguishes ID presence, but the handler does not reject the present-but-null state.

**Reproduction steps:**
1. Enable Transit's MCP server.
2. POST `{ "jsonrpc": "2.0", "id": null, "method": "ping" }` to `/mcp`.
3. Observe a successful ping response with `id: null` instead of JSON-RPC `-32600 Invalid Request`.

**Impact:** MCP clients sending malformed request envelopes receive a positive acknowledgement. The same protocol defect affects single requests and batch members, while notification requests with an omitted ID must continue to execute without a response.

## Investigation Summary

The request model, handler, HTTP route, batch dispatcher, existing T-847 tests, T-847 history, MCP notes, and decode-classification regressions were inspected.

- **Symptoms examined:** Explicit null IDs currently reach method dispatch and return successful results; omitted IDs are intentionally suppressed; string and integer IDs work; batches preserve invalid members and response arrays.
- **Code inspected:** `MCPTypes.swift` (`JSONRPCRequest` presence tracking and response encoding), `MCPToolHandler.swift` (`handle` notification suppression), `MCPServer.swift` (single and batch routing), `MCPServerDecodeTypes.swift`, `MCPNullIdTests.swift`, and `MCPServerBatchRequestTests.swift`.
- **Hypotheses tested:** The decoder losing ID presence was ruled out: `container.contains(.id)` already sets `isNotification` correctly. Batch handling was also ruled out as the primary cause: it delegates request members to the same handler and preserves null-ID error envelopes. T-847's generic JSON-RPC expectation that explicit null should receive a response is obsolete for this MCP endpoint because MCP 2025-03-26 forbids null request IDs.

## Discovered Root Cause

`JSONRPCRequest` represents an explicit null ID as `id == nil` plus `isNotification == false`, which is sufficient to preserve presence. `MCPToolHandler.handle` only checks `request.id` indirectly through the final notification suppression and therefore dispatches the present-but-null request as a normal method call.

**Defect type:** Missing protocol validation at the handler boundary.

**Why it occurred:** T-847 intentionally fixed the ambiguity between omitted IDs and explicit null IDs according to generic JSON-RPC semantics. The later MCP protocol revision is stricter, but no MCP-specific validation was added to the now-preserved explicit-null state, and the T-847 regressions encoded the old expectation as successful behavior.

**Contributing factors:** The response encoder correctly emits a null `id` for error envelopes, and batch handling already has the required per-member response structure, so the defect is easy to miss when inspecting only transport serialization.

## Resolution for the Issue

_To be completed after the production fix and validation._

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPNullIdTests.swift`
- `Transit/TransitTests/MCPServerBatchRequestTests.swift`

**Tests:**
- `handlerRejectsExplicitNullIdAsInvalidRequest`
- `invalidNullIdResponseEncodesErrorWithNullId`
- `singleExplicitNullIdReturnsInvalidRequestWithNullId`
- `batchExplicitNullIdIsInvalidWhileStringAndIntegerIdsRemainValid`
- `handlerOmitsResponseForMissingId`

**What they verify:** Presence-aware decoding distinguishes omitted IDs from explicit null IDs; explicit null is rejected with `-32600` and an explicitly encoded JSON null response ID; notifications remain response-free; string and integer IDs remain successful; and the same semantics hold for HTTP single requests and JSON-RPC batches.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/MCPNullIdTests.swift` | Replace obsolete T-847 success expectations with MCP 2025-03-26 protocol regressions. |
| `Transit/TransitTests/MCPServerBatchRequestTests.swift` | Add single-route and batch-level null-ID response regressions. |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Pending: reject explicit null IDs as invalid requests. |
| `specs/bugfixes/mcp-rejects-explicit-null-request-ids/report.md` | Investigation and final resolution record. |
| `CHANGELOG.md` | Pending: document the MCP protocol correction. |

## Verification

**Automated:**
- [ ] Regression tests pass
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- [ ] Compare single, notification, valid-ID, and batch response envelopes against MCP 2025-03-26.

## Prevention

- Keep protocol-version-specific validation separate from generic JSON-RPC decoding assumptions.
- Preserve explicit field presence in decoders whenever omitted and null have different protocol meanings.
- Retain route-level single and batch regressions for every request-envelope rule.

## Related

- Transit ticket T-1863
- Supersedes the generic JSON-RPC expectation implemented by T-847 (PR #121).
- MCP 2025-03-26 basic protocol: https://modelcontextprotocol.io/specification/2025-03-26/basic/
