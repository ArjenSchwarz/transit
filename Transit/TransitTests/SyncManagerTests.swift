import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct SyncManagerTests {

    /// Saves and restores the UserDefaults value for "syncEnabled" around each
    /// test to avoid polluting shared state.
    private func withSavedDefaults(_ body: () throws -> Void) rethrows {
        let key = "syncEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    // MARK: - T-699 Regression: setSyncEnabled updates runtime state

    @Test
    func setSyncEnabled_updatesRuntimeState() {
        withSavedDefaults {
            let manager = SyncManager()

            // Start with whatever default is; toggle to the opposite
            let original = manager.isSyncEnabled
            manager.setSyncEnabled(!original)
            #expect(manager.isSyncEnabled == !original)

            // Toggle back
            manager.setSyncEnabled(original)
            #expect(manager.isSyncEnabled == original)
        }
    }

    @Test
    func init_readsCurrentUserDefaultsValue() {
        withSavedDefaults {
            // Set a known value before creating the manager
            UserDefaults.standard.set(false, forKey: "syncEnabled")
            let manager = SyncManager()
            #expect(manager.isSyncEnabled == false)
        }
    }

    @Test
    func setSyncEnabled_persistsToUserDefaults() {
        withSavedDefaults {
            let manager = SyncManager()

            manager.setSyncEnabled(false)
            #expect(UserDefaults.standard.bool(forKey: "syncEnabled") == false)

            manager.setSyncEnabled(true)
            #expect(UserDefaults.standard.bool(forKey: "syncEnabled") == true)
        }
    }

    @Test
    func setSyncEnabled_false_stopsHeartbeat() {
        withSavedDefaults {
            let manager = SyncManager()
            // Simulate a running heartbeat by starting one (requires a context,
            // but we can verify via isHeartbeatRunning after disable).
            // Even without an active heartbeat, disabling sync must nil the task.
            manager.setSyncEnabled(false)
            #expect(manager.isSyncEnabled == false)
            #expect(manager.isHeartbeatRunning == false)
        }
    }

    @Test
    func setSyncEnabled_reEnable_doesNotRestartHeartbeat() {
        withSavedDefaults {
            let manager = SyncManager()
            // Disable then re-enable: heartbeat should NOT auto-restart
            manager.setSyncEnabled(false)
            #expect(manager.isHeartbeatRunning == false)

            manager.setSyncEnabled(true)
            #expect(manager.isSyncEnabled == true)
            #expect(manager.isHeartbeatRunning == false,
                    "Re-enabling sync must not restart the heartbeat; a new startHeartbeat call is required")
        }
    }

    // MARK: - T-1699 Regression: heartbeat singleton fetch failures

    private struct FetchFailure: Swift.Error {}

    private final class HeartbeatFetchController {
        var shouldFail = false

        func fetch(
            context: ModelContext,
            descriptor: FetchDescriptor<SyncHeartbeat>
        ) throws -> [SyncHeartbeat] {
            if shouldFail {
                throw FetchFailure()
            }
            return try context.fetch(descriptor)
        }
    }

    private func heartbeatCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<SyncHeartbeat>()).count
    }

    @Test
    func heartbeatWithMissingSingletonInsertsAndSavesOneRecord() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        let manager = SyncManager()

        manager.beat(context: context)

        #expect(try heartbeatCount(in: context) == 1)
        #expect(!context.hasChanges,
                "A successful missing-singleton heartbeat must save its newly inserted record")
    }

    @Test
    func heartbeatWithExistingSingletonUpdatesAndSavesWithoutInsertingAnotherRecord() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        let existing = SyncHeartbeat()
        existing.lastBeat = .distantPast
        context.insert(existing)
        try context.save()
        let manager = SyncManager()

        manager.beat(context: context)

        #expect(try heartbeatCount(in: context) == 1)
        #expect(existing.lastBeat > .distantPast)
        #expect(!context.hasChanges,
                "A successful existing-singleton heartbeat must save its updated timestamp")
    }

    @Test
    func heartbeatFetchFailureDoesNotInsertOrSaveAndNextBeatRecovers() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        let pendingProject = Project(name: "Pending", description: "", gitRepo: nil, colorHex: "")
        context.insert(pendingProject)
        let fetcher = HeartbeatFetchController()
        let manager = SyncManager(heartbeatFetcher: fetcher.fetch)
        fetcher.shouldFail = true

        manager.beat(context: context)

        #expect(try heartbeatCount(in: context) == 0,
                "A failed singleton fetch must not be treated as a missing record")
        #expect(context.hasChanges,
                "A failed singleton fetch must return before it can save unrelated pending changes")

        fetcher.shouldFail = false
        manager.beat(context: context)

        #expect(try heartbeatCount(in: context) == 1,
                "The next heartbeat must retry normally after a transient fetch failure")
        #expect(!context.hasChanges,
                "The recovered heartbeat should retain the normal best-effort save behavior")
    }

    @Test
    func heartbeatFetchFailureKeepsTimerScheduledForNextInterval() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let fetcher = HeartbeatFetchController()
            fetcher.shouldFail = true
            let manager = SyncManager(heartbeatFetcher: fetcher.fetch)

            manager.startHeartbeat(context: fixture.context)
            defer { manager.stopHeartbeat() }
            manager.beat(context: fixture.context)

            #expect(manager.isHeartbeatRunning,
                    "A failed beat must leave the existing timer scheduled to retry at its next interval")
        }
    }
}
