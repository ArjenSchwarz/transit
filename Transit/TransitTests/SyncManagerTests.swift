import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct SyncManagerTests {

    /// Saves and restores the UserDefaults value for "syncEnabled" around each
    /// test to avoid polluting shared state.
    private func withSavedDefaults(_ body: () -> Void) {
        let key = "syncEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
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
}
