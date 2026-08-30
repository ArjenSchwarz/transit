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
- `Transit/Transit/MCP/MCPSettings.swift` - publishes a tool-list invalidation only when the maintenance setting actually changes.
- `Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift` - owns active notification streams, buffers the newest idempotent invalidation, broadcasts changes, and removes terminated streams.
- `Transit/Transit/MCP/MCPToolHandler.swift` - advertises `tools.listChanged: true` and exposes the settings-scoped notification stream to the transport.
- `Transit/Transit/MCP/MCPServer.swift` - validates and routes negotiated GET `/mcp` notification requests.
- `Transit/Transit/MCP/MCPServer+ToolListNotifications.swift` - negotiates `Accept: text/event-stream` and frames server notifications as deterministic SSE data events.

**Approach rationale:** This implements MCP 2025-03-26's native cache-invalidation mechanism. It preserves the existing live `tools/list` behavior, requires no app or listener restart, and adds only the transport feature needed for connected clients to learn that their cache is stale. Buffering one pending event is sufficient because list-change notifications are idempotent: a client always refreshes the current full list.

**Alternatives considered:**
- Restart the Hummingbird listener on toggle — rejected because POST requests are stateless and restarting the server does not make a client discard its cached tools.
- Add UI text requiring manual reconnection — rejected because Decision 9 explicitly targets a no-restart maintenance session and MCP provides a standard list-change notification.
- Add stateful MCP session IDs solely for this notification — deferred because the protocol makes sessions optional and a server-wide list invalidation can be delivered through each negotiated listening stream without adding session lifecycle and header validation to every existing request.

## Regression Test

**Test file:** `Transit/TransitTests/MCPToolListChangeNotificationTests.swift`
**Test name:** `maintenanceToggleAfterInitializeNotifiesConnectedClient`

**What it verifies:** Initialization advertises `tools.listChanged`, GET `/mcp` supplies an SSE listening stream, and changing the maintenance toggle emits exactly one `notifications/tools/list_changed` event to a client that initialized before the change.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `CHANGELOG.md` | Records the completed T-2169 behavior. |
| `Transit/Transit/MCP/MCPSettings.swift` | Publishes real maintenance-toggle changes. |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Advertises list changes and provides the stream. |
| `Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift` | Broadcasts buffered invalidations to active streams. |
| `Transit/Transit/MCP/MCPTypes.swift` | Defines capability and notification payloads. |
| `Transit/Transit/MCP/MCPServer.swift` | Validates and routes negotiated GET/SSE requests. |
| `Transit/Transit/MCP/MCPServer+ToolListNotifications.swift` | Serves the negotiated GET/SSE listening channel. |
| `Transit/TransitTests/MCPServerRouteTests.swift` | Clarifies the non-SSE GET compatibility contract. |
| `Transit/TransitTests/MCPToolListChangeNotificationTests.swift` | Covers multi-client toggle fan-out and same-value notification suppression. |
| `docs/agent-notes/mcp-server.md` | Documents the SSE transport and cache invalidation flow. |
| `specs/bugfixes/mcp-maintenance-toggle-client-refresh/report.md` | Records investigation, resolution, and verification. |

## Verification

**Automated:**
- [x] Focused T-2169 regression passes (`MCPToolListChangeNotificationTests`)
- [x] macOS unit suite passes (`make test-quick`)
- [x] iOS simulator suite passes (`make test`: 1,286 tests, 0 failures)
- [x] UI suite passes (`make test-ui`: 21 tests, 0 failures)
- [x] macOS build passes (`make build-macos`)
- [x] Linters and SwiftData ownership validator pass (`make lint`)

**Manual verification:**
- The focused in-process HTTP smoke test initializes a client, opens two negotiated SSE streams, toggles maintenance tools once, and verifies both clients receive the canonical `notifications/tools/list_changed` event without reconnecting.
- A direct broadcaster regression verifies assigning the existing maintenance-tools value does not emit a spurious notification.

## Prevention

**Recommendations to avoid similar bugs:**
- Treat dynamic MCP capability changes as both data updates and cache-invalidation events.
- Test state changes from the perspective of a client initialized before the change, not only with fresh list calls.

## Related

- Transit T-2169
- `specs/duplicate-displayid-cleanup/decision_log.md` Decision 9
- MCP 2025-03-26 tools list-change notification and Streamable HTTP transport specifications
