# MCP Server (macOS only)

## Overview

Embedded MCP server in the Transit macOS app using Hummingbird HTTP server. Exposes task management tools to Claude Code and other MCP clients via Streamable HTTP transport (`POST /mcp`). All code behind `#if os(macOS)` guards.

## Architecture

```
Claude Code ←→ HTTP POST /mcp (localhost:3141) ←→ MCPServer ←→ MCPToolHandler ←→ TaskService/ProjectService/CommentService ←→ SwiftData
```

- **Transport**: Streamable HTTP, single `POST /mcp` endpoint, JSON-RPC 2.0
- **HTTP server**: Hummingbird 2.x (SwiftNIO-based), binds to `127.0.0.1` only
- **Lifecycle**: Opt-in via Settings toggle. Default port 3141.

## Files

- `Transit/Transit/MCP/MCPTypes.swift` — All Codable protocol types (JSON-RPC, MCP)
- `Transit/Transit/MCP/MCPSettings.swift` — UserDefaults-backed settings (`isEnabled`, `port`)
- `Transit/Transit/MCP/MCPToolHandler.swift` — Tool dispatch, handler methods, helpers
- `Transit/Transit/MCP/MCPToolDefinitions.swift` — Tool schema definitions (extracted for file length)
- `Transit/Transit/MCP/MCPServer.swift` — Hummingbird server lifecycle and HTTP routing
- `Transit/TransitTests/MCPToolHandlerTests.swift` — Unit tests

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
| `query_tasks` | List tasks with optional status/type/project filters; includes comments |
| `add_comment` | Add a comment to a task (by displayId or taskId); always sets `isAgent: true` |

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

## Task Resolution

Task resolution (looking up a task by display ID or UUID) is centralised in `TaskService.resolveTask(from:)`:
- `resolveTask(from identifier: String)` — accepts display ID as integer string or UUID string
- `resolveTask(from dict: [String: Any])` — accepts dictionary with `displayId` or `taskId` keys, uses `IntentHelpers.parseIntValue` for numeric handling

MCPToolHandler, App Intents, and IntentHelpers all delegate to these methods rather than implementing their own resolution logic.

## Gotchas

- `nonisolated` on struct/enum declarations is essential in this project due to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, all types inherit MainActor isolation, breaking Codable conformance on NIO threads.
- `ByteBuffer(data:)` requires explicit `import NIOFoundationCompat` — not available from just `import Hummingbird`.
- Don't reference `self` in `Task.detached` closures on `MCPServer` — causes "sending 'self' risks data races" error. Capture dependencies explicitly.
- **Name-based filters must handle cross-project duplicates.** Milestone names (and potentially other name-resolved entities) can be duplicated across projects. When filtering by name without a project scope, use `Set<UUID>` to collect all matching IDs rather than taking just the first match (T-292).
- **Multi-field updates must be atomic.** When a handler updates multiple fields (e.g., status + name), validate all inputs before mutating any model state, then save once. Don't call separate service methods that each `save()` independently — a failure in the second leaves the first already persisted (T-391).
- **Always pass `save: false` when calling service methods from handlers.** Service methods like `setMilestone` default to `save: true` for standalone use, but handlers must defer saving to a single atomic `save()` at the end. Always add `safeRollback()` in the catch block of that save (T-531).
- **Do not add compensating unescape/transform logic for JSON-RPC input.** JSON-RPC transport handles string encoding correctly: `\n` in JSON decodes to a real newline, `\\n` decodes to literal backslash-n. A previous `unescapeNewlines` helper that globally replaced `\n` with real newlines corrupted legitimate content (T-576 reverted T-561). Pass MCP string arguments through to the service layer unmodified.
- **Always validate `displayId` and `milestoneDisplayId` before use.** When a handler accepts an integer ID from args, check `args["key"] != nil` first, then `IntentHelpers.parseIntValue(args["key"])`. If the key is present but the value is not a valid integer (string, float), return an error immediately — never silently fall through to broader queries or alternate resolution paths. Pattern established in T-613 (milestoneDisplayId) and T-634 (displayId across all handlers).
- **Always validate UUID filter parameters separately from presence checks.** Never use `flatMap(UUID.init)` or combined conditionals like `if let str = ..., let uuid = UUID(str)` for user-provided filter values — these silently drop invalid inputs. Instead, first check if the key is present, then validate the UUID format with a guard, returning an explicit error on failure. See `handleQueryTasks` for the correct pattern; `handleQueryMilestones` uses `resolveProjectFilter` helper (T-665).
- **Always validate enum filter values in query handlers.** When a handler accepts `status`, `not_status`, or `type` as filter parameters, validate each value against the enum's `allCases` before using them. Invalid values must return `isError: true` with a message listing valid options — never silently filter to empty results. Helper: `validateEnumFilter(_:key:type:)` in `MCPToolHandler` — generic over any `RawRepresentable & CaseIterable` enum with `String` raw values (T-732).
