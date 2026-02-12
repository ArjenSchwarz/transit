# MCP Server (macOS only)

## Overview

Embedded MCP server in the Transit macOS app using Hummingbird HTTP server. Exposes task management tools to Claude Code and other MCP clients via Streamable HTTP transport (`POST /mcp`). All code behind `#if os(macOS)` guards.

## Architecture

```
Claude Code ←→ HTTP POST /mcp (localhost:3141) ←→ MCPServer ←→ MCPToolHandler ←→ TaskService/ProjectService ←→ SwiftData
```

- **Transport**: Streamable HTTP, single `POST /mcp` endpoint, JSON-RPC 2.0
- **HTTP server**: Hummingbird 2.x (SwiftNIO-based), binds to `127.0.0.1` only
- **Lifecycle**: Opt-in via Settings toggle. Default port 3141.

## Files

- `Transit/Transit/MCP/MCPTypes.swift` — All Codable protocol types (JSON-RPC, MCP)
- `Transit/Transit/MCP/MCPSettings.swift` — UserDefaults-backed settings (`isEnabled`, `port`)
- `Transit/Transit/MCP/MCPToolHandler.swift` — Tool definitions, argument parsing, service calls
- `Transit/Transit/MCP/MCPServer.swift` — Hummingbird server lifecycle and HTTP routing
- `Transit/TransitTests/MCPToolHandlerTests.swift` — 17 unit tests

## Actor Isolation Pattern

Key challenge: Hummingbird runs on SwiftNIO event loops (nonisolated), but services are `@MainActor`.

1. **MCP protocol types** (`MCPTypes.swift`): All marked `nonisolated` and `Sendable` to opt out of the project's default `@MainActor` isolation. Without this, `Encodable`/`Decodable` conformances become MainActor-isolated and can't be used from NIO threads.
2. **MCPToolHandler**: `@MainActor` class — holds service references, handles tool dispatch.
3. **MCPServer**: `@MainActor @Observable` for SwiftUI environment. Runs Hummingbird in `Task.detached`. Route handler calls `await handler.handle(request)` — Swift concurrency automatically hops to MainActor.
4. **AnyCodable**: Uses `@unchecked Sendable` because it wraps `Any`.

## Tools Exposed

| Tool | Description |
|------|-------------|
| `create_task` | Create a new task (name, type required; project, description optional) |
| `update_task_status` | Change task status (by displayId or taskId) |
| `query_tasks` | List tasks with optional status/type/project filters |

## JSON-RPC Methods Handled

`initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`

## Dependencies

- **Hummingbird 2.x** — Transit's first (and only) external SPM dependency
- Added via Xcode SPM integration in project.pbxproj
- Also pulls in SwiftNIO transitively

## Entitlements

Added `com.apple.security.network.server` and `com.apple.security.network.client` to `Transit.entitlements`.

## Testing with curl

```bash
# List tools
curl -X POST http://localhost:3141/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

# Create task
curl -X POST http://localhost:3141/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_task","arguments":{"name":"Test","type":"feature"}}}'
```

## Claude Code Integration

```bash
claude mcp add transit --transport http http://localhost:3141/mcp
```

## Gotchas

- `nonisolated` on struct/enum declarations is essential in this project due to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, all types inherit MainActor isolation, breaking Codable conformance on NIO threads.
- `ByteBuffer(data:)` requires explicit `import NIOFoundationCompat` — not available from just `import Hummingbird`.
- Don't reference `self` in `Task.detached` closures on `MCPServer` — causes "sending 'self' risks data races" error. Capture dependencies explicitly.
