# Sync Heartbeat Implementation Plan

## Context

When tasks are created or updated on iPhone/iPad, the macOS MCP server doesn't reflect those changes until CloudKit syncs — which can lag significantly because macOS throttles background CloudKit push delivery. A local SwiftData write reliably triggers a full `NSPersistentCloudKitContainer` sync cycle (export + import), so a periodic timestamp write forces remote changes to be pulled.

## Approach

Write a `SyncHeartbeat` SwiftData model (singleton record) and update its `lastBeat` timestamp every 60 seconds while the MCP server is running on macOS. The write triggers CloudKit to pull pending remote changes as a side effect.

## Tasks

### 1. Add `SyncHeartbeat` SwiftData model

**File:** `Transit/Transit/Models/SyncHeartbeat.swift` (new)

Minimal singleton model:
- `id: String` — fixed to `"sync-heartbeat"` (no `@Attribute(.unique)` — CloudKit doesn't support it)
- `lastBeat: Date` — updated each tick

Fetch-or-create by predicate on the fixed `id` string, same pattern used elsewhere in the codebase.

### 2. Add `beat(context:)` to `SyncManager`

**File:** `Transit/Transit/Services/SyncManager.swift`

Add a method that:
1. Fetches the singleton `SyncHeartbeat` by its fixed `id` using `FetchDescriptor`
2. Creates it if missing, otherwise updates `lastBeat` to `Date()`
3. Calls `context.save()`

Guard on `isSyncEnabled` — no point beating if CloudKit sync is off.

### 3. Wire heartbeat timer in `TransitApp` (macOS only)

**File:** `Transit/Transit/TransitApp.swift`

Add a `Task` that loops with `Task.sleep(for: .seconds(60))` while the MCP server is running:
- Start the loop in the existing `.task { startMCPServerIfEnabled() }` block, after starting the server
- Cancel the task when the server stops or the view disappears
- Gate on `!Self.isUnitTestHost` (already guarded by `startMCPServerIfEnabled`)
- Gate on `syncManager.isSyncEnabled`
- Use `nonisolated(unsafe)` for the context reference, matching the existing `connectivityMonitor.onRestore` pattern

### 4. Register `SyncHeartbeat` in schema

**Files:**
- `Transit/Transit/TransitApp.swift` — add `SyncHeartbeat.self` to the `Schema` array
- `Transit/TransitTests/TestModelContainer.swift` — add `SyncHeartbeat.self` to the test schema

### 5. Verify unit test isolation

The `isUnitTestHost` guard in `TransitApp.init()` prevents MCP server startup, which prevents the heartbeat timer from starting. No additional guards needed, but verify by running `make test-quick`.

## File Change Summary

| File | Change |
|------|--------|
| `Models/SyncHeartbeat.swift` | New — SwiftData model |
| `Services/SyncManager.swift` | Add `beat(context:)` method |
| `TransitApp.swift` | Add to schema, wire heartbeat timer (macOS) |
| `TestModelContainer.swift` | Add to test schema |

## Things to Watch

- **CloudKit rate limits**: One small write per 60s is well within private database limits. Don't go below 30s.
- **Heartbeat syncs to all devices**: Benign for a single-user app — each device getting the write triggers its own sync cycle, keeping all devices fresher. The record is tiny (one string + one date).
- **Timer cleanup**: The `Task` must be cancelled when the MCP server stops and when the view disappears. Using a stored `Task` reference with cancellation handles both.
- **No `@Attribute(.unique)`**: CloudKit doesn't support unique constraints. The singleton pattern relies on fetch-by-predicate instead.
