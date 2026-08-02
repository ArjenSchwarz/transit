# Bugfix Report: Unknown MCP Tools Return the Wrong JSON-RPC Code

**Date:** 2026-08-02
**Status:** Fixed
**Transit ticket:** T-1883

## Description of the Issue

Transit advertises MCP protocol version `2025-03-26`, but a supported `tools/call` request with an unknown tool name returns JSON-RPC `methodNotFound` (`-32601`). The outer method is supported; only the `name` parameter is invalid, so MCP clients receive the wrong classification. The same wrong code is used when a maintenance tool is known but disabled in Settings and therefore omitted from `tools/list`.

**Reproduction steps:**
1. Send `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"invalid_tool_name","arguments":{}}}` to `POST /mcp`.
2. Observe an error code of `-32601`.
3. Disable maintenance tools and call `scan_duplicate_display_ids`; observe the same code despite the useful disabled-tool message.

**Expected:** Both supported `tools/call` cases return `JSONRPCErrorCode.invalidParams` (`-32602`) while preserving their useful messages. `tools/list` continues to omit disabled maintenance tools, and an unknown top-level method continues to return `-32601`.

**Impact:** MCP clients may treat a malformed tool name as an unsupported protocol method, leading to incorrect retry, capability, or fallback behavior.

## Investigation Summary

- **Symptoms examined:** Handler and HTTP route responses for arbitrary unknown tool names, disabled maintenance tools, `tools/list`, and unknown top-level methods.
- **Code inspected:** `MCPToolHandler.handle(_:)`, `handleToolCall`, `MCPToolDefinitions`, existing maintenance gating tests, and `MCPServer.makeRouter` route dispatch.
- **Hypotheses tested:** The protocol method dispatch is correct; the defect is isolated to tool-name classification after `tools/call` has already been recognized.

## Discovered Root Cause

`MCPToolHandler.handleToolCall` used `methodNotFound` in both the disabled-maintenance gate and the default tool-name branch. This conflated an unsupported JSON-RPC method with an invalid tool argument to the supported `tools/call` method.

**Defect type:** Logic error — incorrect error classification.

**Why it occurred:** The handler reused the JSON-RPC method-not-found code for tool dispatch failures, even though MCP tool names are parameters of a supported method and the negotiated protocol requires invalid parameters (`-32602`).

**Contributing factors:** Maintenance tools are intentionally omitted from `tools/list` when disabled, which made the existing message useful but did not change the JSON-RPC classification required for a `tools/call` request.

## Resolution for the Issue

The handler now classifies both tool-name failure paths as invalid parameters while leaving the unsupported top-level method path unchanged.

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — changed the disabled-maintenance gate and unknown-tool fallback from `JSONRPCErrorCode.methodNotFound` to `JSONRPCErrorCode.invalidParams`; retained the existing disabled and unknown-tool messages.
- `Transit/TransitTests/MCPToolHandlerTests.swift` — added arbitrary unknown-tool handler coverage and retained the existing unknown top-level method assertion for `-32601`.
- `Transit/TransitTests/MCPMaintenanceHandlerTests.swift` — updated both disabled maintenance-tool cases to assert `-32602` and exact message preservation; existing `tools/list` omission coverage remains unchanged.
- `Transit/TransitTests/MCPServerBatchRequestTests.swift` — added a route-level `POST /mcp` assertion for HTTP 200 plus JSON-RPC `-32602`.
- `docs/agent-notes/mcp-server.md` — corrected the documented disabled-tool code.

**Approach rationale:** The smallest safe fix is to change only the two error-code selections inside `handleToolCall`. `handle(_:)` continues to use `methodNotFound` for unsupported top-level methods, and the maintenance gate still provides a distinct actionable message while `tools/list` remains settings-driven.

**Alternatives considered:**
- Return `methodNotFound` for disabled maintenance tools because they are omitted from `tools/list` — rejected; the request still invokes the supported `tools/call` method and the negotiated contract classifies the invalid tool parameter as `-32602`.
- Change the messages or remove the disabled-tool distinction — rejected; callers benefit from the existing actionable Settings guidance.
- Add a new error code — rejected; JSON-RPC already defines the required `invalidParams` code.


## Regression Test

**Test files:**
- `Transit/TransitTests/MCPToolHandlerTests.swift` — arbitrary unknown tool name at the handler boundary.
- `Transit/TransitTests/MCPMaintenanceHandlerTests.swift` — disabled maintenance-tool behavior.
- `Transit/TransitTests/MCPServerBatchRequestTests.swift` — unknown tool name through the HTTP route.

**What it verifies:** A supported `tools/call` with an unknown or disabled tool name returns `-32602` and preserves the existing message; `tools/list` omission and top-level unknown-method behavior remain covered by existing tests.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Classify unknown and disabled tool names as `invalidParams` while preserving top-level method errors. |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | Add arbitrary unknown-tool handler regression and preserve top-level method coverage. |
| `Transit/TransitTests/MCPMaintenanceHandlerTests.swift` | Assert disabled maintenance tools return `-32602` with their existing messages. |
| `Transit/TransitTests/MCPServerBatchRequestTests.swift` | Add route-level unknown-tool JSON-RPC regression. |
| `docs/agent-notes/mcp-server.md` | Align maintenance-tool behavior documentation with `invalidParams`. |
| `CHANGELOG.md` | Record the T-1883 protocol classification fix. |
| `specs/bugfixes/unknown-mcp-tools-return-the-wrong-json-rpc-code/report.md` | Document investigation, resolution, and verification. |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full macOS unit test suite passes via `make test-quick`
- [x] SwiftLint and repository validators pass via `make lint` (0 violations in 319 files)

**Manual verification:**
- [x] Route-level test confirms `POST /mcp` returns HTTP 200 with a JSON-RPC `-32602` error for an unknown tool.
- [x] Existing tests confirm disabled tools remain absent from `tools/list` and unsupported top-level methods remain `-32601`.

## Prevention

- Keep JSON-RPC method errors separate from errors caused by parameters to supported MCP methods.
- Add route-level coverage for protocol classification changes, not only direct handler tests.
- Preserve useful error messages and capability-list behavior when changing error codes.

## Related

- MCP Tools specification: https://modelcontextprotocol.io/specification/2025-03-26/server/tools
- Transit ticket T-1883
