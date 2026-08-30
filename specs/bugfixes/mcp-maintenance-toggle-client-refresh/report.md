# Bugfix Report: MCP Maintenance Toggle Client Refresh

**Date:** 2026-08-30
**Status:** Fixed

## Description of the Issue

Changing **Expose maintenance tools** updates `MCPSettings.maintenanceToolsEnabled`, and a new `tools/list` request immediately reflects the new value, but clients initialized before the change are not told that their cached tool list is stale.

**Reproduction steps:**
1. Initialize an MCP client while maintenance tools are disabled and cache the ten tools returned by `tools/list`.
2. Enable **Expose maintenance tools** in Transit Settings without reconnecting the client.
3. Observe that the client receives no `notifications/tools/list_changed` notification and continues using its cached list.

**Impact:** Active MCP clients cannot discover newly enabled maintenance tools and can retain disabled tools until they manually refresh or reconnect. The setting therefore appears ineffective during an active session.

## Investigation Summary

The investigation followed a structured inspection of setting persistence, handler dispatch, initialization capabilities, HTTP transport routes, tests, and the accepted maintenance-tool design decision.

- **Symptoms examined:** Fresh `tools/list` calls see the toggle, but initialized clients do not refresh when it changes.
- **Code inspected:** `MCPSettings.swift`, `MCPToolHandler.swift`, `MCPTypes.swift`, `MCPServer.swift`, `SettingsView.swift`, `TransitApp.swift`, MCP handler/route tests, and duplicate-displayid-cleanup Decision 9.
- **Hypotheses tested:** Stale `UserDefaults` state and cached handler definitions were ruled out because the handler reads the live setting on every `tools/list`. Restarting the listener was rejected because the current HTTP transport is stateless between POSTs and a listener restart does not invalidate a client-side tool cache.

### Systematic inspection findings

1. **Data flow:** `MCPSettings.maintenanceToolsEnabled.didSet` only persists to `UserDefaults`; it has no change-observation output.
2. **Protocol capability:** `MCPToolsCapability` encodes an empty object, so clients have no reason to expect list-change notifications.
3. **Transport integration:** GET `/mcp` deliberately returns HTTP 405, leaving no independent server-to-client SSE stream for notifications.
4. **UI integration:** the Settings toggle only mutates the setting and does not notify or reconnect MCP clients.
5. **Test gap:** the existing toggle test issues a second `tools/list` manually, proving live reads but not active-client refresh.

## Discovered Root Cause

Transit implemented dynamic tool-list computation but not the MCP list-change contract or a server-to-client delivery channel.

**Defect type:** Missing protocol/transport integration and state-change notification.

**Why it occurred:**
1. Why does an active client keep the old tools? Because it caches `tools/list` and receives no invalidation notification.
2. Why is no invalidation sent? Because the maintenance setting only persists its new value and has no notification publisher.
3. Why would a client not expect an invalidation? Because initialization advertises an empty tools capability rather than `listChanged: true`.
4. Why can the server not push the notification anyway? Because Transit implements only POST responses and explicitly rejects the Streamable HTTP GET/SSE listening channel.
5. Why did existing coverage miss this? Because it tested a manually repeated list request rather than an initialized client with a cached list.

**Contributing factors:** Decision 9 specified no app restart, but the initial implementation interpreted that as “the next list call is live” rather than “connected clients are invalidated.” The original embedded-server pattern intentionally chose a minimal POST-only transport, which was sufficient until server-initiated notifications were needed.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPTypes.swift` - added `listChanged` to the tools capability and a typed server-notification envelope.
- `Transit/Transit/MCP/MCPSettings.swift` - publishes a tool-list invalidation only when the maintenance setting actually changes and owns notification sessions.
- `Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift` - groups active streams by session, emits each JSON-RPC notification on only one stream per session, and finishes registrations when their channels close.
- `Transit/Transit/MCP/MCPToolHandler.swift` - advertises `tools.listChanged: true` and exposes session/stream lifecycle operations to the transport.
- `Transit/Transit/MCP/MCPRequestContext.swift` - retains each Hummingbird request channel so an idle SSE registration can observe its close future directly.
- `Transit/Transit/MCP/MCPServer.swift` - creates a unique `Mcp-Session-Id` after successful standalone initialization, validates and routes GET `/mcp`, and finishes notification sessions during listener teardown.
- `Transit/Transit/MCP/MCPServer+ToolListNotifications.swift` - validates session headers, parses exact `text/event-stream` media ranges and RFC quality values (including `q=0`), and frames deterministic SSE data events.

**Approach rationale:** This implements MCP 2025-03-26's native cache-invalidation mechanism while preserving the transport rule that one JSON-RPC message must not be duplicated across a client's concurrent listening streams. Session IDs identify which streams belong to one initialized client. Channel-close futures remove idle disconnected streams promptly, rather than waiting for a later notification write. Buffering one pending event remains sufficient because list-change notifications are idempotent: a client always refreshes the current full list.

**Alternatives considered:**
- Restart the Hummingbird listener on toggle — rejected because POST requests are stateless and restarting the server does not make a client discard its cached tools.
- Add UI text requiring manual reconnection — rejected because Decision 9 explicitly targets a no-restart maintenance session and MCP provides a standard list-change notification.
- Broadcast once per SSE connection without sessions — rejected because one client may open concurrent listening streams and MCP forbids sending the same JSON-RPC message more than once.
- Depend only on `AsyncStream.onTermination` for disconnect cleanup — rejected because an idle socket close should remove its registration immediately and independently of response-task cancellation/write timing.

## Regression Test

**Test files:** `Transit/TransitTests/MCPToolListChangeNotificationTests.swift` and `Transit/TransitTests/MCPServerRouteTests.swift`

**What they verify:**
- Successful initialization advertises `tools.listChanged` and creates distinct client session IDs.
- Two streams in one session receive exactly one canonical notification between them, while a second session independently receives one notification.
- Closing an idle transport channel promptly unregisters its stream; same-value setting assignments remain silent.
- GET rejects missing/unknown sessions, zero or malformed quality values, and media-type superstrings; a valid positive-quality exact media range negotiates SSE.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `CHANGELOG.md` | Records the completed session-aware behavior. |
| `Transit/Transit/MCP/MCPSettings.swift` | Publishes real changes and owns notification sessions. |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Advertises list changes and bridges session lifecycle. |
| `Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift` | Deduplicates delivery per session and unregisters closed streams. |
| `Transit/Transit/MCP/MCPTypes.swift` | Defines capability and notification payloads. |
| `Transit/Transit/MCP/MCPRequestContext.swift` | Retains the request transport channel. |
| `Transit/Transit/MCP/MCPServer.swift` | Creates session IDs and routes/tears down GET/SSE sessions. |
| `Transit/Transit/MCP/MCPServer+Responses.swift` | Builds JSON responses with optional session headers. |
| `Transit/Transit/MCP/MCPServer+ToolListNotifications.swift` | Validates sessions, negotiates SSE, and frames notifications. |
| `Transit/TransitTests/MCPHTTPTestHelpers.swift` | Supports the custom context and response/session headers. |
| `Transit/TransitTests/MCPServerOriginValidationTests.swift` | Uses the production request context in origin regressions. |
| `Transit/TransitTests/MCPServerRouteTests.swift` | Covers negotiation and session rejection boundaries. |
| `Transit/TransitTests/MCPToolListChangeNotificationTests.swift` | Covers per-session delivery and prompt disconnect cleanup. |
| `docs/agent-notes/mcp-server.md` | Documents the session-aware SSE transport. |
| `specs/bugfixes/mcp-maintenance-toggle-client-refresh/report.md` | Records investigation, artifact fixes, and verification. |

## Verification

The original T-2169 implementation passed focused tests, `make test-quick`, `make test`, `make test-ui`, `make build-macos`, and `make lint` before the artifact review. For this session/deduplication, channel-close cleanup, and strict negotiation follow-up:
- Bounded focused `MCPToolListChangeNotificationTests`: passed (3 tests).
- `make test-quick`: passed after the final source-file refactor.
- `make lint`: passed, including the SwiftData ownership guard and 358 Swift files with zero violations.
- `git diff --check`: passed.

**Manual verification represented by regressions:**
- The in-process HTTP test initializes two client sessions, opens two streams for one session and one for the other, toggles maintenance tools once, and verifies exactly one canonical event per session.
- Direct lifecycle regressions verify same-value suppression and prompt removal when an idle channel closes.

## Prevention

**Recommendations to avoid similar bugs:**
- Treat dynamic MCP capability changes as both data updates and cache-invalidation events.
- Test state changes from the perspective of a client initialized before the change, not only with fresh list calls.

## Related

- Transit T-2169
- `specs/duplicate-displayid-cleanup/decision_log.md` Decision 9
- MCP 2025-03-26 tools list-change notification and Streamable HTTP transport specifications
