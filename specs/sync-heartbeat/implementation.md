# Sync Heartbeat — Implementation Explanation

## Beginner Level

### What Changed

Transit is a task tracker that syncs data between your iPhone and Mac using Apple's CloudKit. When you create or update a task on your iPhone, the Mac version should see the change. In practice, macOS can be slow to notice those changes — sometimes taking minutes because macOS aggressively throttles background sync notifications.

This change adds a "heartbeat" — a tiny write to the database every 60 seconds on the Mac, but only while the MCP server (the interface that AI agents use to query tasks) is running. The write itself is meaningless (just a timestamp), but it has a useful side effect: it wakes up the sync engine, which then checks for and downloads any pending changes from other devices.

### Why It Matters

Without this, an AI agent querying tasks via the MCP server could get stale data — tasks created on iPhone might not appear for several minutes. With the heartbeat, the worst-case staleness is ~60 seconds.

### Key Concepts

- **CloudKit**: Apple's cloud database that syncs data across your devices
- **MCP server**: A local HTTP server inside Transit on macOS that lets AI agents read and write tasks
- **Heartbeat**: A periodic "ping" — like a clock ticking every minute — that keeps the sync engine awake
- **SwiftData**: Apple's framework for storing data locally, which handles CloudKit sync automatically

---

## Intermediate Level

### Changes Overview

| File | Purpose |
|------|---------|
| `Models/SyncHeartbeat.swift` | New `@Model` — singleton record with `id` + `lastBeat` |
| `Services/SyncManager.swift` | `startHeartbeat(context:)`, `stopHeartbeat()`, private `beat(context:)` |
| `TransitApp.swift` | Schema registration, heartbeat wired to MCP server startup |
| `Views/ScenePhaseModifier.swift` | Extracted from TransitApp.swift (lint fix, no functional change) |
| `TestModelContainer.swift` | Schema updated to include `SyncHeartbeat` |

### Implementation Approach

The mechanism exploits `NSPersistentCloudKitContainer`'s behavior: any local save triggers a full sync cycle (export local changes + import remote changes). The heartbeat writes a timestamp to a singleton `SyncHeartbeat` record, which is enough to trigger the import.

**Singleton pattern**: `SyncHeartbeat` uses a fixed `id` string (`"sync-heartbeat"`) instead of `@Attribute(.unique)` (which CloudKit doesn't support). The `beat()` method fetches by predicate; if no record exists, it creates one.

**Timer**: A `Task` loop with `Task.sleep(for: .seconds(60))` runs on the main actor (inherited from `SyncManager`'s `@MainActor` isolation). Started when the MCP server starts, cancelled via stored `Task` reference.

**Guards**: The heartbeat only starts if (a) MCP server is enabled, (b) not running in unit test host, and (c) CloudKit sync is enabled.

### Trade-offs

- **60-second interval**: Chosen to stay well within CloudKit private database rate limits while providing acceptable freshness. The ticket notes not to go below 30 seconds.
- **Heartbeat syncs to all devices**: Each device receiving the heartbeat write triggers its own sync cycle. For a single-user app this is benign and actually keeps all devices fresher.
- **No `@Attribute(.unique)`**: CloudKit incompatibility means the singleton relies on fetch-by-predicate. A second record with the same ID is theoretically possible during a race, but harmless — the fetch returns the first match.

---

## Expert Level

### Technical Deep Dive

The implementation leverages a known `NSPersistentCloudKitContainer` behavior: `context.save()` with any dirty object triggers `NSCloudKitMirroringDelegate` to schedule both an export and an import. The export pushes the heartbeat timestamp (trivial payload), and the import pulls any pending server changes. This is the same mechanism that makes local edits propagate — we're just forcing a sync cycle with a sacrificial write.

**Property defaults**: All `@Model` properties use inline defaults (`var id: String = "sync-heartbeat"`), not just `init()` assignments. This is required for CloudKit lightweight migration — without inline defaults, `NSPersistentCloudKitContainer` fails to open the store after schema changes, falling back to the in-memory container (discovered and fixed during development).

**Actor isolation**: `SyncManager` is `@MainActor` (via default isolation). The `Task` created in `startHeartbeat` inherits this isolation, so `beat(context:)` runs on the main actor — safe for `ModelContext` access without `nonisolated(unsafe)` wrappers.

**Error handling**: `try? context.save()` silently swallows save errors. This is intentional — the heartbeat is non-critical infrastructure. If a save fails, the next beat in 60 seconds retries. This matches the pattern in `initializeCloudKitSchemaIfNeeded` in the same class.

### Architecture Impact

- **Schema**: `SyncHeartbeat` is the fifth SwiftData entity. It's registered in both the app schema and test schema. It participates in CloudKit sync (the record appears in the private database on all devices).
- **Lifecycle**: Tied to MCP server startup via `startMCPServerIfEnabled()`. No explicit stop on MCP disable — the Task is cleaned up on process termination. This is acceptable because the MCP server itself runs for the app's lifetime once started.
- **No coupling**: The heartbeat doesn't affect any other service. Other services don't know it exists. The `SyncHeartbeat` record is never queried by anything other than `beat()`.

### Potential Issues

- **CloudKit schema migration**: Adding `SyncHeartbeat` to an existing CloudKit schema is an additive migration — always safe. But the inline default values are critical; without them, the migration fails silently and triggers the fallback in-memory container.
- **Multiple macOS instances**: If the user somehow runs two instances of Transit on macOS, both would heartbeat independently. Harmless but wasteful.
- **Sync disabled at runtime**: If the user disables sync while the heartbeat is running, the writes still happen locally but don't trigger CloudKit (no CloudKit configuration on the container). The writes are harmless — they update a local record that goes nowhere.

---

## Completeness Assessment

### Fully Implemented
- SyncHeartbeat model with correct CloudKit-compatible defaults
- Heartbeat timer management in SyncManager (start/stop/beat)
- MCP server lifecycle integration (macOS only)
- Schema registration in app and tests
- Guards for sync enabled and unit test host

### Not Implemented (by design)
- No UI for heartbeat status (spec says "invisible to the user")
- No dedicated unit tests (straightforward fetch-or-create + save; verified via integration)
- No explicit `stopHeartbeat()` call site (process cleanup handles it)
