# Bugfix Report: MCP Rejects Valid JSON-RPC Batch Requests

**Date:** 2026-08-01
**Status:** Fixed
**Transit ticket:** T-1834

## Description of the Issue

Transit advertises MCP protocol version `2025-03-26`, whose Streamable HTTP transport permits a POST body containing a non-empty JSON-RPC batch of requests and notifications. The embedded MCP server decodes every POST body directly as one `JSONRPCRequest`, so every array is rejected with a single `-32600 Invalid Request` response.

**Reproduction steps:**
1. Enable Transit's MCP server.
2. POST `[{"jsonrpc":"2.0","id":1,"method":"ping"}]` to `/mcp`.
3. Observe a single `-32600 Invalid Request` object instead of an array containing the ping response.

**Impact:** Standards-compliant MCP clients cannot batch calls against Transit. Mixed batches lose all valid requests, notification-only batches return HTTP 200 with an error body instead of HTTP 202 with no body, and the advertised protocol contract is not met.

## Investigation Summary

### Phase 1: Initial overview

- **Expected behaviour:** A non-empty request/notification batch is processed element by element; notifications produce no JSON-RPC response; request responses remain wrapped in an array; all-notification batches return HTTP 202 with no body; malformed batch elements produce per-element `-32600` responses; empty batches produce one `-32600` response object; `initialize` is rejected when batched.
- **Actual behaviour:** Any top-level array fails structural decoding as one `JSONRPCRequest` and returns one `-32600` response object.
- **Context:** The defect occurs for every batch POST, independent of the methods or IDs in the batch.

### Phase 2: Systematic inspection

- **Data flow defect — `Transit/Transit/MCP/MCPServer.swift`:** `decodeIncomingRequest(_:)` parses the JSON root but then always decodes the original bytes as one `JSONRPCRequest`; it has no single-versus-batch envelope.
- **Logic defect — `Transit/Transit/MCP/MCPServer.swift`:** `makeRouter(handler:)` dispatches exactly one request and can encode exactly one response.
- **Boundary defect — empty array:** JSON-RPC requires a single invalid-request object for an empty batch, distinct from non-empty invalid batches whose errors are returned in an array.
- **Lifecycle defect — batched initialize:** MCP 2025-03-26 states that `initialize` MUST NOT be part of a JSON-RPC batch, but the current transport has no batch context in which to enforce that rule.
- **Response-shape defect:** JSON-RPC requires a batch response array even when a valid batch contains only one request; notification responses must be omitted rather than represented as null or empty entries.

### Phase 3: Root cause analysis

1. Why are valid batches rejected? Because the decoder expects one request object.
2. Why does it expect one object? Because `DecodeOutcome.success` carries only `JSONRPCRequest`.
3. Why can the route not recover? Because dispatch and response encoding are also single-message only.
4. Why was this accepted? The original HTTP endpoint implemented the common one-request-per-POST path without mirroring the batching clause of the advertised Streamable HTTP protocol.
5. Why do lifecycle and HTTP status errors follow from the same omission? Batch context is required to reject `initialize`, omit notification responses, choose an array response, and detect an all-notification POST.

**Root cause:** The transport model represents a POST body as one JSON-RPC request instead of a JSON-RPC single-or-batch envelope.

**Assumptions validated:** The MCP 2025-03-26 transport specification explicitly allows non-empty request/notification arrays and requires HTTP 202 for notification-only input. Its lifecycle specification explicitly forbids `initialize` in a batch. JSON-RPC 2.0 defines empty and invalid batch response shapes.

### Phase 4: Solution and verification

Implement a top-level decode outcome that preserves single-request compatibility and adds non-empty batch elements. Decode each batch element independently so malformed members become per-element `-32600` responses. Dispatch valid elements through the existing `MCPToolHandler`, reject non-notification `initialize` elements before handler dispatch, collect only non-nil responses, and encode collected batch responses as an array. Return HTTP 202 with no body when no response remains.

Verification will cover mixed requests/notifications, all-notification HTTP 202, empty batches, invalid members, batched initialize, batch response arrays, and unchanged single-request object responses.

## Discovered Root Cause

The MCP HTTP transport has no representation of a JSON-RPC batch envelope. Its decoder, dispatcher, and encoder are each hard-coded to exactly one request and one response.

**Defect type:** Protocol integration and boundary-handling omission.

**Why it occurred:** The initial implementation covered single JSON-RPC request/notification POSTs but did not implement the batching requirements of MCP protocol `2025-03-26` that the server later advertised.

**Contributing factors:** Batch rules span JSON parsing, MCP lifecycle validation, JSON-RPC response shape, and HTTP status selection, so handling only the structural decoder would still leave the endpoint non-compliant.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPServer.swift` now distinguishes single requests from non-empty batch envelopes, retains invalid members for per-element errors, handles empty batches as one invalid request, dispatches batch elements sequentially, rejects batched `initialize`, returns response arrays for batches, and returns HTTP 202 with no body when no responses remain.
- `Transit/Transit/MCP/MCPToolHandler.swift` now executes valid notification method/tool paths before suppressing their response, rather than dropping notifications before dispatch.
- JSON response encoding now accepts either a single `JSONRPCResponse` or `[JSONRPCResponse]` without changing single-request response shape.

**Approach rationale:** Keeping envelope parsing and HTTP response-shape decisions in `MCPServer` preserves the existing request dispatcher while giving it the batch context needed for MCP lifecycle validation. Sequential dispatch is legal under JSON-RPC and avoids nondeterministic mutations on Transit's shared MainActor SwiftData context.

**Alternatives considered:**
- Decode a Codable single-or-array enum directly. Rejected because independently invalid batch members must survive decoding and produce their own `-32600` responses instead of failing the whole array.
- Dispatch batch elements concurrently. Rejected because JSON-RPC does not require concurrency and deterministic ordering is safer for state-changing task tools sharing one model context.
- Reject an entire batch when it contains `initialize`. Rejected because per-member handling preserves valid sibling requests while returning a lifecycle error for the invalid initialize member.

## Regression Test

**Test file:** `Transit/TransitTests/MCPServerBatchRequestTests.swift`

**Tests:**
- `mixedRequestAndNotificationBatchReturnsOnlyRequestResponses`
- `allNotificationBatchReturnsAcceptedWithNoBody`
- `toolCallNotificationIsDispatchedButGetsNoResponse`
- `emptyBatchReturnsSingleInvalidRequestObject`
- `invalidBatchMembersEachProduceAnErrorResponse`
- `initializeInsideBatchIsRejectedWithoutRejectingOtherRequests`
- `singleRequestStillReturnsAResponseObject`

**What they verify:** Streamable HTTP status handling, notification side effects, lifecycle enforcement, and externally visible JSON-RPC object-versus-array response semantics at the real Hummingbird router boundary.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPServer.swift` | Batch envelope decoding, dispatch, lifecycle validation, and response encoding |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Execute notifications while omitting their responses |
| `Transit/TransitTests/MCPServerBatchRequestTests.swift` | Focused route-level regression coverage |
| `Transit/TransitTests/MCPRequestDecodeErrorClassificationTests.swift` | Existing single-request decode assertions made exhaustive for batch outcomes |
| `docs/agent-notes/mcp-server.md` | Batch semantics and maintenance guidance |
| `specs/bugfixes/mcp-rejects-valid-json-rpc-batch-requests/report.md` | Investigation and resolution record |
| `CHANGELOG.md` | User-visible T-1834 fix summary |

## Verification

**Automated:**
- [x] Regression tests fail before the fix: `make test-quick PIPE_PRETTY=''` discovered the new suite and failed exactly the unsupported batch behaviours. Empty-batch and unchanged single-request controls passed.
- [x] Regression tests and the full macOS unit suite pass: `make test-quick`.
- [x] SwiftLint and the model-container ownership guard pass: `make lint`.
- [x] The affected macOS app builds: `make build-macos`.
- [~] `make test` and `make test-ui` were attempted but could not produce a clean iOS result. Xcode repeatedly failed to connect to an attached device's `com.apple.mobile.notification_proxy`, emitted `DebuggerVersionStore` errors, and the commands hit the harness timeout. The UI run also reproduced six unrelated existing UI failures (`testClearAll`, `testEditViewPreservesTaskMilestone`, three Settings navigation tests, and `testDataMaintenanceGoldenPath`). T-1834 changes are macOS-only and the macOS suite is green.

**Manual verification:**
- The route-level tests collect and inspect the real Hummingbird response body, confirming response arrays, null IDs for invalid members, content type, and empty HTTP 202 bodies without requiring a separately launched app process.

## Prevention

- Model protocol envelopes explicitly rather than assuming one message per transport operation.
- Add transport-level tests whenever the advertised MCP protocol version changes.
- Keep JSON-RPC batch rules and MCP lifecycle restrictions covered independently.

## Related

- Transit ticket T-1834
- MCP 2025-03-26 Streamable HTTP transport: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#sending-messages-to-the-server
- MCP 2025-03-26 lifecycle: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle#initialization
- JSON-RPC 2.0 batching: https://www.jsonrpc.org/specification#batch
