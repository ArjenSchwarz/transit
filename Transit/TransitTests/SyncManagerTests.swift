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

    // MARK: - T-1937 Regression: heartbeat follows launch mode

    @Test
    func startHeartbeatSchedulesForCloudActiveLaunch() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let manager = SyncManager()
            manager.recordActiveCloudSync(true)
            manager.startHeartbeat(container: fixture.container)
            defer { manager.stopHeartbeat() }

            #expect(manager.isHeartbeatRunning,
                    "A CloudKit-active launch must schedule its heartbeat without a preference change")
        }
    }

    @Test
    func settingSyncOffKeepsHeartbeatRunningForCloudActiveLaunch() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let manager = SyncManager()
            manager.recordActiveCloudSync(true)
            manager.startHeartbeat(container: fixture.container)
            defer { manager.stopHeartbeat() }

            manager.setSyncEnabled(false)

            #expect(manager.isSyncEnabled == false)
            #expect(manager.syncChangeRequiresRestart)
            #expect(manager.isHeartbeatRunning,
                    "A restart-scoped preference change must not stop the active launch heartbeat")
        }
    }

    @Test
    func settingSyncOnDoesNotStartHeartbeatForCloudInactiveLaunch() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(false, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let manager = SyncManager()
            manager.recordActiveCloudSync(false)
            manager.setSyncEnabled(true)
            manager.startHeartbeat(container: fixture.container)

            #expect(manager.isSyncEnabled)
            #expect(manager.syncChangeRequiresRestart)
            #expect(!manager.isHeartbeatRunning,
                    "A preference change cannot enable a CloudKit-free container before relaunch")
        }
    }

    @Test
    func revertingSyncPreferenceLeavesActiveLaunchHeartbeatRunning() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let manager = SyncManager()
            manager.recordActiveCloudSync(true)
            manager.startHeartbeat(container: fixture.container)
            defer { manager.stopHeartbeat() }

            manager.setSyncEnabled(false)
            manager.setSyncEnabled(true)

            #expect(!manager.syncChangeRequiresRestart)
            #expect(manager.isHeartbeatRunning,
                    "Reverting the preference must leave the launch-scoped heartbeat unchanged")
        }
    }

    @Test
    func explicitHeartbeatStopStillControlsActiveLaunchLifecycle() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let manager = SyncManager()
            manager.recordActiveCloudSync(true)
            manager.startHeartbeat(container: fixture.container)
            manager.setSyncEnabled(false)

            manager.stopHeartbeat()

            #expect(!manager.isHeartbeatRunning,
                    "Explicit MCP lifecycle shutdown must still stop the heartbeat")
        }
    }

    // MARK: - T-1699 Regression: heartbeat singleton fetch failures

    private struct FetchFailure: Swift.Error {}
    private struct SaveFailure: Swift.Error {}

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

    private final class HeartbeatSaveController {
        var shouldFail = false

        func save(context: ModelContext) throws {
            if shouldFail {
                throw SaveFailure()
            }
            try context.save()
        }
    }

    private func heartbeatCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<SyncHeartbeat>()).count
    }

    private func projectCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<Project>()).count
    }

    // MARK: - T-2232 Regression: heartbeat context isolation

    @Test
    func successfulHeartbeatDoesNotSaveUnrelatedPendingChanges() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        context.insert(Project(name: "Pending", description: "", gitRepo: nil, colorHex: ""))
        let manager = SyncManager()

        manager.beat(container: fixture.container)

        // Expected: the heartbeat commits independently. Actual before T-2232: saving
        // the caller's context also committed this pending project.
        #expect(context.hasChanges,
                "A successful heartbeat must leave the caller's pending changes unsaved")
        let verificationContext = ModelContext(fixture.container)
        #expect(try heartbeatCount(in: verificationContext) == 1)
        #expect(try projectCount(in: verificationContext) == 0,
                "A successful heartbeat must not persist unrelated caller-context models")
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

        manager.beat(container: fixture.container)

        let verificationContext = ModelContext(fixture.container)
        let storedHeartbeat = try #require(
            verificationContext.fetch(FetchDescriptor<SyncHeartbeat>()).first
        )
        #expect(try heartbeatCount(in: verificationContext) == 1)
        #expect(storedHeartbeat.lastBeat > .distantPast)
    }

    @Test
    func heartbeatFetchFailureDoesNotInsertOrSaveAndNextBeatRecoversInIsolation() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        context.insert(Project(name: "Pending", description: "", gitRepo: nil, colorHex: ""))
        let fetcher = HeartbeatFetchController()
        let manager = SyncManager(heartbeatFetcher: fetcher.fetch)
        fetcher.shouldFail = true

        manager.beat(container: fixture.container)

        let failedBeatVerification = ModelContext(fixture.container)
        #expect(try heartbeatCount(in: failedBeatVerification) == 0,
                "A failed singleton fetch must not be treated as a missing record")
        #expect(context.hasChanges,
                "A failed singleton fetch must leave unrelated caller changes pending")

        fetcher.shouldFail = false
        manager.beat(container: fixture.container)

        let recoveredBeatVerification = ModelContext(fixture.container)
        #expect(try heartbeatCount(in: recoveredBeatVerification) == 1,
                "The next heartbeat must retry normally after a transient fetch failure")
        #expect(context.hasChanges,
                "A recovered heartbeat must still leave unrelated caller changes pending")
        #expect(try projectCount(in: recoveredBeatVerification) == 0,
                "Recovery must not persist unrelated caller-context models")
    }

    @Test
    func heartbeatSaveFailureDoesNotDirtyCallerContextAndNextBeatRecovers() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        let existing = SyncHeartbeat()
        existing.lastBeat = .distantPast
        context.insert(existing)
        try context.save()
        context.insert(Project(name: "Pending", description: "", gitRepo: nil, colorHex: ""))
        let saver = HeartbeatSaveController()
        let manager = SyncManager(heartbeatSaver: saver.save)
        saver.shouldFail = true

        manager.beat(container: fixture.container)

        // Expected: only an isolated heartbeat context becomes dirty and is discarded.
        // Actual before T-2232: the shared heartbeat model remains mutated in the caller.
        #expect(existing.lastBeat == .distantPast,
                "A failed heartbeat save must not leave heartbeat state dirty in the caller context")
        #expect(context.hasChanges,
                "The caller's unrelated pending project must remain pending")
        let failedBeatVerification = ModelContext(fixture.container)
        let storedAfterFailure = try #require(
            failedBeatVerification.fetch(FetchDescriptor<SyncHeartbeat>()).first
        )
        #expect(storedAfterFailure.lastBeat == .distantPast)
        #expect(try projectCount(in: failedBeatVerification) == 0)

        saver.shouldFail = false
        manager.beat(container: fixture.container)

        let recoveredBeatVerification = ModelContext(fixture.container)
        let storedAfterRecovery = try #require(
            recoveredBeatVerification.fetch(FetchDescriptor<SyncHeartbeat>()).first
        )
        #expect(storedAfterRecovery.lastBeat > .distantPast)
        #expect(context.hasChanges)
        #expect(try projectCount(in: recoveredBeatVerification) == 0)
    }

    @Test
    func heartbeatFetchFailureKeepsTimerScheduledForNextInterval() throws {
        try withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let fixture = try TestModelContainer()
            let fetcher = HeartbeatFetchController()
            fetcher.shouldFail = true
            let manager = SyncManager(heartbeatFetcher: fetcher.fetch)

            manager.startHeartbeat(container: fixture.container)
            defer { manager.stopHeartbeat() }
            manager.beat(container: fixture.container)

            #expect(manager.isHeartbeatRunning,
                    "A failed beat must leave the existing timer scheduled to retry at its next interval")
        }
    }
}
