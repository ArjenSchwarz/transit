# PR Review Overview - Iteration 1

**PR**: #9 | **Branch**: T-2/mcp-server | **Date**: 2026-02-13

## Valid Issues

### Code-Level Issues

#### Issue 1: Race condition in MCPServer.isRunning state management
- **File**: `Transit/Transit/MCP/MCPServer.swift:20-21, 55-60`
- **Reviewer**: External code review
- **Comment**: When the user toggles the MCP server off and then quickly back on, the old detached task's cleanup callback (`setNotRunning()`) will unconditionally set `isRunning = false`, even though a new server instance may be running. The closure has no mechanism to distinguish whether it belongs to the currently active server or a stale cancelled task.
- **Validation**: Confirmed. The `setNotRunning` closure at line 60 fires when the detached task ends, regardless of whether a new server has started since. Sequence: `stop()` → `start()` → old task finishes → `isRunning` becomes `false` while new server is running. Fix: use a generation counter to discard stale callbacks.

#### Issue 2: Protocol violation — notifications must not receive a JSON-RPC response
- **File**: `Transit/Transit/MCP/MCPServer.swift:44-45`, `Transit/Transit/MCP/MCPToolHandler.swift:22-23`
- **Reviewer**: External code review + @chatgpt-codex-connector (P1)
- **Comment**: The handler returns a `JSONRPCResponse` for `notifications/initialized`, and the route always wraps it in an HTTP 200 JSON body. JSON-RPC 2.0 spec says "The Server MUST NOT reply to a Notification" and MCP Streamable HTTP transport expects 202/204 with no body. Spec-conformant clients may fail the handshake.
- **Validation**: Confirmed. Both the handler (which constructs a response for the notification) and the route (which always serializes a response) need changes. The handler should signal "no response needed" and the route should return HTTP 202 with an empty body for notifications.

#### Issue 3: Restart server when MCP port changes
- **File**: `Transit/Transit/Views/Settings/SettingsView.swift:66, 76-78`
- **Reviewer**: @chatgpt-codex-connector (P2)
- **Comment**: The server lifecycle only reacts to `isEnabled` changes. Editing the port while the server is running updates settings/UI but leaves the server bound to the old port. The displayed `claude mcp add` command points to the new port that is not actually listening.
- **Validation**: Confirmed. The `onChange(of:)` only watches `mcpSettings.isEnabled`. Port changes via the TextField have no effect on the running server. Fix: add an `onChange(of: mcpSettings.port)` that restarts the server when enabled.

#### Issue 4: Reject malformed projectId in query_tasks
- **File**: `Transit/Transit/MCP/MCPToolHandler.swift:205-208`
- **Reviewer**: @chatgpt-codex-connector (P2)
- **Comment**: If `projectId` is provided but is not a valid UUID, `UUID(uuidString:)` returns nil and the filter is silently skipped, turning an intended scoped query into an unfiltered full-task query.
- **Validation**: Confirmed. A typo like `"projectId":"abc"` returns all tasks. Fix: return an error when the provided string is not a valid UUID.

## Invalid/Skipped Issues

_None — all identified issues are valid._
