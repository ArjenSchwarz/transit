# MCP Server Implementation Plan

## Context

The Transit design doc specifies an MCP server as a "thin translation layer over App Intents" that runs locally on macOS and invokes intents via Shortcuts. Instead of that architecture (separate process → Shortcuts CLI → App Intents), we embed the MCP server directly in the Transit macOS app using Hummingbird as an HTTP server. This gives us direct access to `TaskService` and `ProjectService` — no Shortcuts roundtrip, no JSON re-serialization through intents.

The MCP server exposes 3 tools matching the existing App Intents: `create_task`, `update_task_status`, `query_tasks`. It uses the Streamable HTTP transport (POST `/mcp`) and binds to localhost only.

## Architecture

```
Claude Code ←→ HTTP POST /mcp (localhost:3141) ←→ MCPServer ←→ TaskService/ProjectService ←→ SwiftData/CloudKit
```

- **Transport**: Streamable HTTP — single `POST /mcp` endpoint, JSON-RPC 2.0
- **HTTP server**: Hummingbird (lightweight, Swift 6 ready, SwiftNIO-based)
- **Protocol**: Direct implementation (no MCP SDK — protocol surface is small, SDK is pre-1.0 with no HTTP server transport)
- **Platform**: macOS only (`#if os(macOS)` guards). iOS/iPadOS don't need local MCP.
- **Lifecycle**: Opt-in via Settings toggle. Server starts/stops with the toggle. Binds to `127.0.0.1` only.

### Actor Isolation

Services are `@MainActor`. Hummingbird runs on SwiftNIO event loops (background threads). The bridge:
1. Route handler receives HTTP POST on NIO thread
2. Parses JSON-RPC request (nonisolated, pure data)
3. `await`s a `@MainActor` method on `MCPToolHandler` to execute the tool call
4. Swift concurrency handles the hop automatically
5. Response returned to NIO thread

`MCPToolHandler` is `@MainActor` (holds service references). `MCPServer` manages the Hummingbird lifecycle in a detached task so `Application.run()` doesn't block the main actor.

## Dependencies

**Add via Xcode SPM** (not Package.swift — Transit uses Xcode native):

- `hummingbird` — [github.com/hummingbird-project/hummingbird](https://github.com/hummingbird-project/hummingbird) (latest 2.x)

This is Transit's first external dependency. Hummingbird pulls in SwiftNIO transitively. Both support all Apple platforms even though we only use them on macOS.

## New Files

### `Transit/Transit/MCP/MCPServer.swift`
Server lifecycle and HTTP routing. Responsibilities:
- Create Hummingbird `Application` with router
- `POST /mcp` route handler: parse JSON-RPC, dispatch to `MCPToolHandler`, return response
- `start(port:)` / `stop()` methods
- Runs `Application.run()` in a detached `Task` so it doesn't block MainActor
- Binds to `127.0.0.1` only (localhost)
- All code wrapped in `#if os(macOS)`

### `Transit/Transit/MCP/MCPToolHandler.swift`
`@MainActor` class that holds `TaskService` and `ProjectService` references. Handles:
- `initialize` → return server info and capabilities (`tools` capability only)
- `tools/list` → return tool definitions with JSON Schema input schemas
- `tools/call` → dispatch by tool name to handler methods
- `ping` → return empty response
- Individual tool methods: `handleCreateTask()`, `handleUpdateStatus()`, `handleQueryTasks()`
- Error mapping: service errors → MCP error responses (reuse `IntentError` codes)

### `Transit/Transit/MCP/MCPTypes.swift`
Codable types for the MCP protocol:
- `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCError` — JSON-RPC 2.0 envelope types
- `MCPInitializeParams`, `MCPInitializeResult` — handshake types
- `MCPToolDefinition`, `MCPToolCallParams`, `MCPToolResult` — tool types
- `MCPCapabilities`, `MCPServerInfo` — capability declaration

### `Transit/Transit/MCP/MCPSettings.swift`
`@Observable` class for MCP preferences (macOS only):
- `isEnabled: Bool` (default: `false`, stored in UserDefaults)
- `port: Int` (default: `3141`, stored in UserDefaults)
- Not synced via CloudKit — MCP config is per-machine

## Modified Files

### `Transit/Transit/TransitApp.swift`
- Add `MCPServer` and `MCPToolHandler` as properties (behind `#if os(macOS)`)
- Create `MCPSettings`, `MCPToolHandler` (with service references), and `MCPServer` in `init()`
- Add `.task {}` modifier to start MCP server if enabled
- Inject `MCPSettings` into environment for SettingsView

### `Transit/Transit/Views/Settings/SettingsView.swift`
- Add "MCP Server" section (macOS only, between Appearance and Projects):
  - `Toggle("MCP Server", isOn: $mcpSettings.isEnabled)`
  - Port field (only shown when enabled)
  - Status indicator (running/stopped)
  - Copyable `claude mcp add` command string for easy setup

## Tool Definitions

### `create_task`
```
Input: name (string, required), type (string enum, required),
       projectId (string/UUID, optional), project (string, optional),
       description (string, optional), metadata (object, optional)
Output: { taskId, displayId, status }
```
Calls `ProjectService.findProject()` then `TaskService.createTask()`.

### `update_task_status`
```
Input: displayId (integer) OR taskId (string/UUID), status (string enum, required)
Output: { taskId, displayId, previousStatus, status }
```
Calls `TaskService.findByDisplayID()` or `findByID()`, then `TaskService.updateStatus()`.

### `query_tasks`
```
Input: status (string, optional), type (string, optional),
       projectId (string/UUID, optional)
Output: [{ taskId, displayId, name, status, type, projectId, projectName,
           completionDate, lastStatusChangeDate }]
```
Uses `FetchDescriptor` with predicates built from filters, or queries all and filters in-memory (matching `QueryTasksIntent` behavior).

## Implementation Steps

1. **Add Hummingbird dependency** via Xcode SPM integration
2. **Create `MCPTypes.swift`** — all Codable protocol types
3. **Create `MCPSettings.swift`** — UserDefaults-backed observable settings
4. **Create `MCPToolHandler.swift`** — tool definitions, argument parsing, service calls
5. **Create `MCPServer.swift`** — Hummingbird server lifecycle and routing
6. **Modify `TransitApp.swift`** — create and wire MCP components (macOS only)
7. **Modify `SettingsView.swift`** — add MCP settings section
8. **Write unit tests** for `MCPToolHandler` (using `TestModelContainer` with test services)
9. **Write integration test** — start server, send HTTP requests, verify JSON-RPC responses
10. **Lint and verify** — `make lint`, `make build`, `make test-quick`

## Verification

1. **Build**: `make build-macos` — verify MCP code compiles, iOS build still works
2. **Unit tests**: Test tool handlers in isolation with in-memory SwiftData
3. **Manual integration test**:
   - Enable MCP in Settings, note port
   - `curl -X POST http://localhost:3141/mcp -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'`
   - Verify tool definitions returned
   - Call `tools/call` with `create_task` and verify task created
4. **Claude Code integration**:
   - `claude mcp add transit --transport http http://localhost:3141/mcp`
   - Use Transit tools from Claude Code conversation
5. **Lint**: `make lint`
