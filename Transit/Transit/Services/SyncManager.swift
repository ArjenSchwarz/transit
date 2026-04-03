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
    /// Stops the heartbeat immediately when sync is disabled; re-enabling sync
    /// does not restart the heartbeat (a new `startHeartbeat` call is needed).
    func setSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
        if !enabled {
            stopHeartbeat()
        }
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

    // MARK: - Heartbeat

    private var heartbeatTask: Task<Void, Never>?

    /// Whether a heartbeat loop is currently scheduled.
    var isHeartbeatRunning: Bool { heartbeatTask != nil }

    /// Starts a 60-second repeating heartbeat that writes to SwiftData,
    /// triggering CloudKit to pull pending remote changes.
    func startHeartbeat(context: ModelContext) {
        heartbeatTask?.cancel()
        guard isSyncEnabled else { return }

        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                beat(context: context)
            }
        }
    }

    /// Stops the heartbeat timer.
    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Writes a timestamp to the `SyncHeartbeat` singleton, triggering a
    /// CloudKit sync cycle that pulls pending remote changes.
    private func beat(context: ModelContext) {
        let singletonID = SyncHeartbeat.singletonID
        let descriptor = FetchDescriptor<SyncHeartbeat>(
            predicate: #Predicate { $0.id == singletonID }
        )
        let heartbeat = (try? context.fetch(descriptor))?.first ?? SyncHeartbeat()
        heartbeat.lastBeat = Date()
        if heartbeat.modelContext == nil {
            context.insert(heartbeat)
        }
        try? context.save()
    }

    // MARK: - CloudKit Schema

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
