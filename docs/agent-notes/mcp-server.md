# MCP Server (macOS only)

## Overview

Embedded MCP server in the Transit macOS app using Hummingbird HTTP server. Exposes task management tools to Claude Code and other MCP clients via Streamable HTTP transport (`POST /mcp`). Server, transport and MCP wire/provider adapters are behind `#if os(macOS)` guards. The Foundation read lifecycle is cross-platform; native consolidation history shares the app-owned read coordinator on macOS, iPhone and iPad.

## Architecture

```
Claude Code ←→ HTTP POST + request-scoped POST/SSE /mcp (localhost:3141) ←→ MCPServer ←→ MCPToolHandler ←→ read services / MCPWriteCoordinator ←→ SwiftData
```

- **Transport**: Latest-only MCP `2026-07-28` at `POST /mcp`: server/discover, tools/list, tools/call and request-scoped subscriptions/listen SSE. No initialize, session ID, GET listener or wire arrays. Required metadata/headers and result schemas are documented in [the result contract](../mcp-result-contract.md).
- **HTTP server**: Hummingbird 2.x (SwiftNIO-based), binds to `127.0.0.1` only
- **Lifecycle**: Opt-in via Settings toggle. Default port 3141.

## Files

- `Transit/Transit/MCP/MCPTypes.swift` — All Codable protocol types (JSON-RPC, MCP)
- `Transit/Transit/MCP/MCPSettings.swift` — UserDefaults-backed settings (`isEnabled`, `port`) and settings-scoped tool-list invalidation source
- `Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift` — active SSE stream registration and list-change broadcasting
- `Transit/Transit/MCP/MCPToolHandler.swift` — Tool dispatch, handler methods, helpers
- `Transit/Transit/MCP/MCPToolDefinitions.swift` — Tool schema definitions (extracted for file length)
- `Transit/Transit/MCP/MCPServer.swift` — Hummingbird server lifecycle and modern HTTP routing
- `Transit/Transit/MCP/MCPServer+Responses.swift` — shared JSON response encoding and header construction
- `Transit/Transit/MCP/MCPRequestContext.swift` — request context retaining the NIO channel for disconnect observation
- `Transit/Transit/MCP/MCPServer+ToolListNotifications.swift` — request-scoped POST subscription negotiation and SSE framing
- `Transit/Transit/MCP/MCPServerLifecycleConfiguration.swift` — bounded shutdown and no-signal `ServiceGroup` policy
- `Transit/Transit/MCP/MCPServerDecodeTypes.swift` — request decode outcome types shared by the route and decoder
- `Transit/Transit/MCP/MCPOriginValidator.swift` — transport-level `Origin`/`Host` validation
- `Transit/TransitTests/MCPToolHandlerTests.swift` — Unit tests

## Actor Isolation Pattern

Key challenge: Hummingbird runs on SwiftNIO event loops (nonisolated), but services are `@MainActor`.

1. **MCP protocol types** (`MCPTypes.swift`): All marked `nonisolated` and `Sendable` to opt out of the project's default `@MainActor` isolation. Without this, `Encodable`/`Decodable` conformances become MainActor-isolated and can't be used from NIO threads.
2. **MCPToolHandler**: `@MainActor` class — holds service references, handles tool dispatch.
3. **MCPServer**: `@MainActor @Observable` for SwiftUI environment. A single desired-state lifecycle task serializes start/stop/restart requests. Each active listener retains both its Hummingbird `ServiceGroup` and detached run task; teardown calls `triggerGracefulShutdown()` and then awaits the run task before any replacement bind. Cancelling and awaiting the task is insufficient because Service Lifecycle's cancellation path cancels children instead of invoking Hummingbird's listener-closing `Server.shutdownGracefully()`. Two configuration choices matter: `maximumGracefulShutdownDuration` is set so an in-flight request that never completes cannot suspend `run()` forever and wedge the single lifecycle task, and `gracefulShutdownSignals` is left empty because `runService()`'s SIGTERM/SIGINT default permanently changes the whole process's signal disposition — undesirable in a GUI app, and unnecessary since teardown is driven by `triggerGracefulShutdown()`. Requests that arrive while teardown is suspended overwrite the pending target rather than queueing, so a burst converges on the latest state. Route handlers call `await handler.handle(request)` to hop to MainActor.
4. **AnyCodable**: Uses `@unchecked Sendable` because it wraps `Any`.

## Tools Exposed

All ten standalone write tools require `idempotencyKey`; updates and milestone deletion also require `expectedRevision`. Consolidation writes use exact retained reviewId/reviewRevision rather than a client-authored plan; apply additionally requires explicit preservation acknowledgment. Their saved records and structured retry/conflict outcomes follow [the write contract](../mcp-write-contract.md). Read tools and gated maintenance tools retain their separate dispatch paths.

| Tool | Description |
|------|-------------|
| `create_project` | Create a project (name and colorHex required; description and gitRepo optional). Returns projectId and project metadata for subsequent create_task calls. |
| `get_projects` | List projects with metadata and milestone summaries. |
| `create_task` | Create a new task (name and type required; at least one of project / projectId required to identify the project; description, metadata, and priority optional — priority defaults to medium, invalid priority rejects with no task created) |
| `update_task_status` | Change task status (by displayId or taskId) |
| `update_task` | Update a task's mutable fields — any combination of `name`, `description`, `type`, `priority`, `metadata`, and milestone assignment (`milestone` / `milestoneDisplayId` / `clearMilestone`) — in a single atomic call. Priority is non-clearable: omit to leave unchanged. Identify task by displayId or taskId. |
| `query_tasks` | Required detailLevel, includeComments, and limit (1–100); returns frozen {results,nextCursor,expiresAt} pages. Existing filters or single displayId; taskIds/displayIds batches reject filters. Continuations send cursor and optional identical retained readPolicy. |
| `add_comment` | Add a comment to a task (by displayId or taskId); always sets `isAgent: true` |
| `preview_task_consolidation` | Saved bounded review of one survivor and one to five same-project candidates, with explicit preservation accounting; no write key or domain effects. |
| `consolidate_tasks` | Commit the exact retained review with preservationAcknowledged:true and one protected key; original tasks/comments remain. |
| `preview_task_consolidation_undo` | Inspect immutable operation history and current whole-reversal availability; retain an undo review when available. |
| `undo_task_consolidation` | Whole reversal against the exact retained review/current evidence, or saved already-reversed reconciliation. |

### Task query snapshots (T-2379)

`MCPTaskQueryRequest` validates initial options and cursor continuation (cursor plus optional identical retained readPolicy). The admitted `MCPReadService` captures saved values, then prepares projected pages, frozen tool fragments and capture metadata through the common result seam before atomic publication. Full queries fetch child-side comments for a complete revision even when bodies are omitted; summary queries without comments can skip that fetch. Repeated selector IDs reuse captured evidence. Continuations retain frozen revisions/text/metadata and add only a newly correlated RPC wrapper, without fetching live records.

`MCPTaskQuerySnapshotStore` retains encoded pages for five minutes with monotonic expiry, at most eight multi-page snapshots and16MiB charged retained data. Capacity rejection preserves existing cursors; reads do not extend lifetime. One-page results are byte-limited but need no retained snapshot. Listener shutdown closes its own admission and clears retained MCP indexes before awaiting listener teardown; unfinished physical read workers retain their slots until finalizers complete; canceled or failed publication cannot expose cursor success. The bounded coordinator retains unfinished physical slots across restart.

### Maintenance tools (gated, default off)

`scan_duplicate_display_ids` and `reassign_duplicate_display_ids` are exposed only when `MCPSettings.maintenanceToolsEnabled` is true. The toggle is persisted under UserDefaults key `mcpMaintenanceToolsEnabled`.

- `MCPToolDefinitions` is split into `coreTools` and `maintenanceTools`; `tools(includingMaintenance:)` returns the right subset. The legacy `all` alias still resolves to `coreTools` only — anything in production should use the helper.
- When the toggle is off, tools/list excludes both maintenance tools. Exposed modern tools/call validation rejects unknown or disabled tool names with HTTP400/-32602, `Tool name is missing or unavailable`, before handler dispatch.
- The toggle takes effect on the next tools/list without restart. Discovery advertises tools.listChanged; subscriptions/listen acknowledges supported requested filters before any change. Each opted-in request stream receives correlated availability changes with bounded coalescing. Disconnect/cancellation/server teardown releases its registration; there are no sessions.
- Dispatch handlers (`handleScanDuplicateDisplayIds`, `handleReassignDuplicateDisplayIds`) encode `DisplayIDMaintenanceTypes` (Codable structs) via a shared `encodedTextResult(_:)` helper that JSON-encodes any `Encodable` and wraps it in the `MCPToolResult.content[text]` envelope.

## Origin / Host Validation (T-1833)

Binding to 127.0.0.1 keeps the *network* out, not the browser running on the same
machine. The MCP Streamable HTTP transport therefore requires `Origin` validation
on every request, and `MCPServer.makeRouter` runs it as the **first statement of
the route**, before `request.body.collect(...)`.

`MCPOriginValidator.rejectionReason(origin:authority:)` encodes the policy:

| Input | Result |
|-------|--------|
| `Origin` absent | allowed — real MCP clients are not browsers and send none |
| `Origin` = `http`/`https` + loopback host (`127.0.0.1`, `localhost`, `::1`) | allowed |
| any other `Origin` (incl. `null`, `file://`, `evil.localhost`, `127.0.0.1.evil.com`) | HTTP 403 |
| `Host` present and not loopback | HTTP 403 — the DNS-rebinding signature |

Gotchas:

- **Never reject a missing `Origin`.** Claude Code and CLI callers send no
  `Origin` header at all; rejecting absence breaks the entire agent integration.
- **Rejections are plain HTTP 403, not JSON-RPC errors.** The request never
  passed protocol validation, and a `200` with an error object would confirm to
  an attacker's page that the endpoint is live. The body is a fixed
  `"Forbidden"` rather than the specific reason, so a prober cannot tell whether
  the `Origin` or the `Host` check tripped.
- **The `Host` header arrives as `request.head.authority`, not
  `headerFields[.host]`.** Hummingbird's `HTTP1ToHTTPServerCodec` calls
  `HTTPRequest(head, secure:splitCookie:)`, which lifts `Host` into the
  authority pseudo-header. The `rawHTTP1*` tests in
  `MCPServerOriginValidationTests` drive that exact conversion, so the mapping
  is proven rather than assumed.
- **Don't parse the origin with `URL`/`URLComponents`.** They are lenient by
  design — `URL(string: "http://127.0.0.1@evil.example.com")?.host` is
  `evil.example.com`. `MCPOriginValidator` parses by hand and fails closed.
- **Host matching is exact.** `*.localhost` resolves to loopback on some
  resolvers, so subdomains are not accepted.
- Any new route added to `MCPServer` must repeat the check. If a second route
  ever appears, promote it to a Hummingbird middleware instead.
- `MCPSettings.validPortRange` is `nonisolated` so the validator (which runs on
  NIO threads) can reuse it.

## Modern request validation

Supported methods: `server/discover`, `tools/list`, `tools/call`, `subscriptions/listen`.
The route validates Origin/Host before collecting at most1MiB, then validates one request object, ID, required per-request metadata and matching protocol/method/name headers before dispatch. Unsupported versions return the supported revision; unknown methods return404. Arrays, initialize, GET listeners, null/missing IDs and unsupported client notifications reject without effects. See [the result contract](../mcp-result-contract.md) for exact fields, response schemas and rejection behavior.

## Dependencies

- **Hummingbird 2.x** — Transit's only *declared* external SPM dependency
- Added via Xcode SPM integration in project.pbxproj
- Also pulls in SwiftNIO and swift-service-lifecycle transitively
- `MCPServer.swift` imports `ServiceLifecycle` directly (for `ServiceGroup`), so
  that transitive module is effectively a source-level dependency even though it
  is not declared as a package product on the target

## Entitlements

Added `com.apple.security.network.server` and `com.apple.security.network.client` to `Transit.entitlements`.

## Client usage and compatibility

Use the request examples and header requirements in [the result contract](../mcp-result-contract.md). Protected effects additionally require the original key/revision evidence from [the write contract](../mcp-write-contract.md). Do not send legacy headerless curl calls or assume a client supports the latest-only endpoint from its version.

Actual Codex/Claude installed-client compatibility is unverified and owner-approved deferred to post-merge MacBook validation. No client configuration or activation is performed by this branch's tests. Validate each intended surface against an isolated synthetic endpoint before relying on it.

## Task Resolution

Task resolution (looking up a task by display ID or UUID) is centralised in `TaskService.resolveTask(from:)`:
- `resolveTask(from identifier: String)` — accepts display ID as integer string or UUID string
- `resolveTask(from dict: [String: Any])` — accepts dictionary with `displayId` or `taskId` keys, uses `IntentHelpers.parseIntValue` for numeric handling

MCPToolHandler, App Intents, and IntentHelpers all delegate to these methods rather than implementing their own resolution logic.

## Gotchas

- `nonisolated` on struct/enum declarations is essential in this project due to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Without it, all types inherit MainActor isolation, breaking Codable conformance on NIO threads.
- Modern request IDs are nonnull strings or signed64-bit integral numbers. Missing IDs/client notifications are rejected without dispatch; a tools/call notification cannot mutate data. Internal legacy decoder types do not define the exposed route.
- `ByteBuffer(data:)` requires explicit `import NIOFoundationCompat` — not available from just `import Hummingbird`.
- Don't reference `self` in `Task.detached` closures on `MCPServer` — causes "sending 'self' risks data races" error. Capture dependencies explicitly.
- **Name-based filters must handle cross-project duplicates.** Milestone names (and potentially other name-resolved entities) can be duplicated across projects. When filtering by name without a project scope, use `Set<UUID>` to collect all matching IDs rather than taking just the first match (T-292).
- **Multi-field updates must be atomic.** When a handler updates multiple fields (e.g., status + name), validate all inputs before mutating any model state, then save once. Don't call separate service methods that each `save()` independently — a failure in the second leaves the first already persisted (T-391).
- **Always pass `save: false` when calling service methods from handlers.** Service methods like `setMilestone` default to `save: true` for standalone use, but handlers must defer saving to a single atomic `save()` at the end. Always add `safeRollback()` in the catch block of that save (T-531).
- **Do not add compensating unescape/transform logic for JSON-RPC input.** JSON-RPC transport handles string encoding correctly: `\n` in JSON decodes to a real newline, `\\n` decodes to literal backslash-n. A previous `unescapeNewlines` helper that globally replaced `\n` with real newlines corrupted legitimate content (T-576 reverted T-561). Pass MCP string arguments through to the service layer unmodified.
- **Always validate `displayId` and `milestoneDisplayId` before use.** When a handler accepts an integer ID from args, check `args["key"] != nil` first, then `IntentHelpers.parseIntValue(args["key"])`. If the key is present but the value is not a valid integer (string, float), return an error immediately — never silently fall through to broader queries or alternate resolution paths. Pattern established in T-613 (milestoneDisplayId) and T-634 (displayId across all handlers).
- **Always validate UUID filter parameters separately from presence checks.** Never use `flatMap(UUID.init)` or combined conditionals like `if let str = ..., let uuid = UUID(str)` for user-provided filter values — these silently drop invalid inputs. Instead, first check if the key is present, then validate the UUID format with a guard, returning an explicit error on failure. See `handleQueryTasks` for the correct pattern; `handleQueryMilestones` uses `resolveProjectFilter` helper (T-665). This applies to both query and create flows — T-743 fixed the same pattern in `handleCreateTask`, `handleCreateMilestone`, `CreateTaskIntent`, and `CreateMilestoneIntent`. The `resolveMilestone` helper also follows this pattern for both `displayId` (T-634) and `milestoneId` (T-769).
- **Always validate enum filter values in query handlers.** When a handler accepts `status`, `not_status`, or `type` as filter parameters, validate each value against the enum's `allCases` before using them. Invalid values must return `isError: true` with a message listing valid options — never silently filter to empty results. Helper: `validateEnumFilter(_:key:type:)` in `MCPToolHandler` — generic over any `RawRepresentable & CaseIterable` enum with `String` raw values (T-732).
- **Reuse IntentHelpers instead of implementing private handler-local helpers.** `IntentHelpers` provides shared utilities for metadata extraction, JSON parsing, task/milestone resolution, and error mapping. Don't duplicate this logic in MCPToolHandler — use the shared version to ensure consistent behavior across MCP and App Intent paths (T-723).
- **`update_task` distinguishes "omit" from "clear".** Omitting a field leaves the stored value untouched; passing `description: ""` or whitespace-only clears the description, and passing `metadata: {}` clears all metadata. A request with only identity and required safety inputs leaves domain state/revision unchanged but persists its replay receipt. MCP returns a full saved record inside a committed outcome; App Intents keep their existing response shape. `UpdateTaskAllFieldsParityTests` compares domain fields after explicitly checking MCP null/empty values and applying Intent omission rules.

## Project creation

`create_project` accepts required `name`, `colorHex`, and `idempotencyKey` strings. Names are trimmed and must be non-empty and unique under the same case-insensitive policy as UI creation. Colors must contain exactly six ASCII hexadecimal digits, optionally prefixed by `#`; case and prefix are preserved. Optional `description` defaults to `""`; both description and gitRepo must be strings when present (JSON null is rejected). Their contents pass through unchanged, and gitRepo remains free-form like the UI field.

Example `tools/call` params:

```json
{"name":"create_project","arguments":{"name":"Agent Work","colorHex":"007AFF","description":"Tasks created through MCP","gitRepo":"git@example.com:team/project.git","idempotencyKey":"agent-project-001"}}
```

Success returns a committed JSON outcome inside `content[0].text`, with the full project in `record`, its UUID in `entityId`, and replay expiry. Pass `record.projectId` to `create_task` with a separate key. `get_projects` includes the new project immediately. Invalid fields, duplicate names, and storage failures return structured error outcomes with `isError: true`. The coordinator commits the project and terminal receipt together and blocks creation while fallback storage is active.
