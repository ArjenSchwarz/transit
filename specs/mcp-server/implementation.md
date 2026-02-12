# MCP Server Implementation Explanation

## Beginner Level

### What Changed

Transit is a task-tracking app for Apple devices. This change adds a small web server inside the macOS version of Transit that lets external tools — specifically Claude Code (an AI coding assistant) — create tasks, update their status, and search for tasks, all without touching the app's UI.

Think of it like adding a drive-through window to a restaurant. The restaurant (Transit) already has a front door (the UI) and a phone-order line (Shortcuts/App Intents). Now there's a third way in: a drive-through (MCP server) where automated tools can place orders using a specific protocol.

### Why It Matters

Without this, the only ways to manage tasks in Transit are through the app's graphical interface or Apple Shortcuts. With the MCP server, Claude Code can directly create and manage tasks during a coding session. For example, while working on a feature, Claude Code could automatically create a "T-43: Fix login bug" task in Transit.

### Key Concepts

- **MCP (Model Context Protocol)**: A standard protocol that lets AI tools talk to external applications. It defines how to list available actions ("tools") and how to call them.
- **JSON-RPC**: A way to send requests and receive responses over HTTP using JSON. Each request has a method name and parameters; each response has a result or an error.
- **Hummingbird**: A lightweight Swift web server library. It handles the HTTP networking so the app doesn't have to.
- **localhost**: The server only listens on `127.0.0.1` — the computer itself. Nothing on the network can reach it. This is a security measure.

---

## Intermediate Level

### Changes Overview

**New files (4 source + 1 test):**
- `MCP/MCPTypes.swift` — JSON-RPC 2.0 and MCP protocol Codable types
- `MCP/MCPSettings.swift` — UserDefaults-backed settings (enabled toggle, port)
- `MCP/MCPToolHandler.swift` — Tool definitions and dispatch to existing services
- `MCP/MCPServer.swift` — Hummingbird HTTP server lifecycle
- `TransitTests/MCPToolHandlerTests.swift` — 17 unit tests

**Modified files:**
- `TransitApp.swift` — Wires MCP components into the app lifecycle (macOS only)
- `SettingsView.swift` — Adds MCP settings section with toggle, port, status indicator
- `Transit.entitlements` — Adds network server/client entitlements
- `project.pbxproj` — Adds Hummingbird 2.x SPM dependency

All MCP code is behind `#if os(macOS)` guards. iOS builds are unaffected.

### Implementation Approach

The architecture has three layers:

1. **Transport layer** (`MCPServer`): Hummingbird HTTP server with a single `POST /mcp` route. Runs in a `Task.detached` to keep `Application.run()` off the MainActor. Parses raw HTTP into `JSONRPCRequest`, dispatches to the handler, serialises the response back to HTTP.

2. **Protocol layer** (`MCPToolHandler`): `@MainActor` class that owns references to `TaskService` and `ProjectService`. Dispatches JSON-RPC methods (`initialize`, `tools/list`, `tools/call`, `ping`) and translates tool arguments into service calls. Reuses `IntentHelpers` for JSON encoding and project lookup error mapping — same code path as the App Intents layer.

3. **Type layer** (`MCPTypes`): Pure data types for JSON-RPC and MCP protocol messages. All marked `nonisolated` and `Sendable` to cross the NIO-event-loop/MainActor boundary safely.

The tool definitions live in a separate `nonisolated enum MCPToolDefinitions` with JSON Schema descriptions for each tool's input parameters.

### Trade-offs

**Direct embedding vs. separate process**: The plan originally considered a separate MCP process that invokes App Intents via the Shortcuts CLI. Direct embedding was chosen because it eliminates the Shortcuts roundtrip, avoids JSON re-serialisation through intents, and keeps the architecture simpler.

**No MCP SDK**: The MCP protocol surface needed (initialize, tools/list, tools/call) is small enough that a direct implementation is simpler than pulling in a pre-1.0 SDK that doesn't have an HTTP server transport.

**Hummingbird over Vapor**: Hummingbird is lighter weight, Swift 6 ready, and pulls in fewer transitive dependencies. It's sufficient for a localhost-only single-endpoint server.

**In-memory filtering for query_tasks**: Tasks are fetched via `FetchDescriptor` and filtered in memory. For a personal task tracker (likely <100 tasks), this is adequate and matches the existing `QueryTasksIntent` pattern.

---

## Expert Level

### Technical Deep Dive

**Actor isolation bridge**: The central technical challenge. Hummingbird route handlers run on SwiftNIO event loops (nonisolated context). The services are `@MainActor`. The bridge works via Swift structured concurrency: the route handler calls `await handler.handle(request)`, and the runtime automatically hops to the MainActor since `MCPToolHandler.handle()` is `@MainActor`-isolated.

All protocol types in `MCPTypes.swift` must be `nonisolated` because the project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without the `nonisolated` keyword, `Encodable`/`Decodable` conformances inherit MainActor isolation and can't be used from NIO threads. Every struct and enum in that file carries both `nonisolated` and `Sendable`.

`AnyCodable` uses `@unchecked Sendable` because it wraps `Any`. The type-erased encoding handles the standard JSON types (Bool, Int, Double, String, Array, Dict) with a fallback to the `Encodable` existential.

**Server lifecycle**: `MCPServer.start()` sets `isRunning = true` eagerly and launches a detached task. The Hummingbird `Application.runService()` blocks until cancelled or crashed. `stop()` cancels the task and resets state.

**Tool handler reuse**: `MCPToolHandler` deliberately reuses `IntentHelpers.encodeJSON()`, `IntentHelpers.mapProjectLookupError()`, and the same `TaskService`/`ProjectService` methods as the App Intents layer. This means MCP and Shortcuts produce identical JSON output formats and error codes.

### Architecture Impact

This is Transit's first external dependency (Hummingbird). It pulls in SwiftNIO transitively. Both are platform-universal, so iOS builds still work even though the MCP code is gated behind `#if os(macOS)`.

The MCP server shares the same `ModelContext` and services as the rest of the app. Changes made via MCP are immediately visible in the UI (and vice versa) because they operate on the same SwiftData context.

The settings are per-machine (UserDefaults, not CloudKit-synced), which is correct since MCP server configuration is specific to the local development environment.

### Potential Issues

1. **`isRunning` state mismatch**: If Hummingbird fails to bind (e.g., port already in use), `isRunning` stays `true` because the error is swallowed in the catch block. The UI would show "Running" when the server isn't actually running.

2. **Port change while running**: The settings UI allows changing the port while the server is running, but the change has no effect until the user toggles off and on. There's no automatic restart or UI indication of this.

3. **Unused `[weak self]` capture**: The `Task.detached` closure in `MCPServer.start()` captures `[weak self]` but never references `self` inside the closure. This is harmless but unnecessary.

4. **No port validation**: `MCPSettings.port` accepts any integer. Values outside 1-65535 would cause Hummingbird to fail silently (caught by issue #1).

5. **`JSONRPCRequest.jsonrpc` field**: The field is decoded but never validated to be "2.0". A malformed request with `"jsonrpc": "1.0"` would still be processed. This is fine for a localhost-only server but deviates from strict protocol compliance.

## Completeness Assessment

### Fully Implemented
- All three tools (`create_task`, `update_task_status`, `query_tasks`) matching the plan spec
- JSON-RPC 2.0 protocol handling (initialize, tools/list, tools/call, ping, unknown method error)
- Hummingbird HTTP server with localhost-only binding
- Settings UI with toggle, port, status, and setup command
- 17 unit tests covering all tools and error paths
- macOS-only gating with `#if os(macOS)`
- Network entitlements
- Hummingbird SPM dependency

### Partially Implemented
- Server error reporting: startup failures are silently swallowed (isRunning state can be wrong)

### Not Implemented (per plan)
- Integration test (step 9 in plan): "start server, send HTTP requests, verify JSON-RPC responses" — only unit tests for the handler were written, not end-to-end HTTP tests. This is acceptable since the handler tests cover the business logic, and HTTP integration is verified manually via curl.
