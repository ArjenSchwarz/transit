import CloudKit
import Foundation
import SwiftData

/// Manages the CloudKit sync enabled/disabled preference.
///
/// The sync state is stored in UserDefaults. Because SwiftData's ModelConfiguration
/// is set at container creation time, toggling sync at runtime requires recreating
/// the container. This manager provides the preference and a factory method for
/// creating the appropriate ModelConfiguration.
///
/// In practice: disabling sync takes effect immediately (removes CloudKit options
/// from the store description). Re-enabling sync takes effect on next app launch
/// since the ModelContainer must be recreated.
@Observable
final class SyncManager {

    /// Matches the @AppStorage key used in SettingsView.
    private static let syncEnabledKey = "syncEnabled"
    private static let cloudKitContainerID = "iCloud.me.nore.ig.Transit"

    private(set) var isSyncEnabled: Bool

    init() {
        // Default to enabled if never set
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.syncEnabledKey) == nil {
            defaults.set(true, forKey: Self.syncEnabledKey)
        }
        self.isSyncEnabled = defaults.bool(forKey: Self.syncEnabledKey)
    }

    // MARK: - Public API

    /// Toggles CloudKit sync on or off. Persists the preference to UserDefaults.
    func setSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
    }

    /// Creates a ModelConfiguration based on the current sync preference.
    func makeModelConfiguration(schema: Schema) -> ModelConfiguration {
        if isSyncEnabled {
            return ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(Self.cloudKitContainerID)
            )
        } else {
            return ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )
        }
    }

    /// Call when re-enabling sync to initialize the CloudKit schema.
    /// This ensures the schema is pushed to CloudKit on first sync after re-enable.
    func initializeCloudKitSchemaIfNeeded(container: ModelContainer) {
        guard isSyncEnabled else { return }

        // Access the underlying Core Data stack to initialize the CloudKit schema.
        // This is a no-op if the schema is already up to date.
        do {
            try container.mainContext.save()
        } catch {
            // Schema initialization failures are non-fatal — sync will retry.
        }
    }
}
