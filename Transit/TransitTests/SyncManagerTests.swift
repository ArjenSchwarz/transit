import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct SyncManagerTests {

    // MARK: - T-699 Regression: setSyncEnabled updates runtime state

    @Test
    func setSyncEnabled_updatesRuntimeState() {
        let manager = SyncManager()

        // Start with whatever default is; toggle to the opposite
        let original = manager.isSyncEnabled
        manager.setSyncEnabled(!original)
        #expect(manager.isSyncEnabled == !original)

        // Toggle back
        manager.setSyncEnabled(original)
        #expect(manager.isSyncEnabled == original)
    }

    @Test
    func init_readsCurrentUserDefaultsValue() {
        // Set a known value before creating the manager
        UserDefaults.standard.set(false, forKey: "syncEnabled")
        let manager = SyncManager()
        #expect(manager.isSyncEnabled == false)

        // Reset
        UserDefaults.standard.set(true, forKey: "syncEnabled")
    }

    @Test
    func setSyncEnabled_persistsToUserDefaults() {
        let manager = SyncManager()

        manager.setSyncEnabled(false)
        #expect(UserDefaults.standard.bool(forKey: "syncEnabled") == false)

        manager.setSyncEnabled(true)
        #expect(UserDefaults.standard.bool(forKey: "syncEnabled") == true)
    }
}
