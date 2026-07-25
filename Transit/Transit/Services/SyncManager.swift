import CloudKit
import Foundation
import SwiftData

/// Manages the CloudKit sync enabled/disabled preference.
///
/// The manager tracks two distinct things, and conflating them was the root of
/// both T-1797 and T-1857:
///
/// - `isSyncEnabled` — the user's *preference*, stored in UserDefaults. It flips
///   the moment the Settings toggle moves.
/// - `isCloudSyncActive` — the CloudKit mode the live `ModelContainer` was actually
///   created with. SwiftData fixes `ModelConfiguration` at container creation, so
///   this is decided once at launch and cannot change for the lifetime of the process.
///
/// Between a toggle and the next launch these two disagree. `syncChangeRequiresRestart`
/// exposes that gap so Settings can tell the user plainly that the change lands after a
/// relaunch (T-1857 — see Decision 21, which rejected live container replacement).
/// Everything that talks to CloudKit directly — notably the display-ID counter — must
/// gate on `isCloudSyncActive`, never on the preference (T-1797).
@Observable
final class SyncManager {

    /// Matches the @AppStorage key used in SettingsView.
    private static let syncEnabledKey = "syncEnabled"
    private static let cloudKitContainerID = "iCloud.me.nore.ig.Transit"

    private(set) var isSyncEnabled: Bool

    /// The CloudKit mode the live `ModelContainer` was built with. Fixed for the
    /// lifetime of the process; see the type doc. Seeded from the preference so a
    /// standalone manager (previews, tests) is self-consistent, then overwritten by
    /// whichever launch path actually creates the container.
    private(set) var isCloudSyncActive: Bool

    /// True when the preference no longer matches the mode the live container runs in,
    /// i.e. the user changed the toggle and has not relaunched yet.
    var syncChangeRequiresRestart: Bool {
        isSyncEnabled != isCloudSyncActive
    }

    init() {
        // Default to enabled if never set
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.syncEnabledKey) == nil {
            defaults.set(true, forKey: Self.syncEnabledKey)
        }
        let enabled = defaults.bool(forKey: Self.syncEnabledKey)
        self.isSyncEnabled = enabled
        self.isCloudSyncActive = enabled
    }

    // MARK: - Public API

    /// Toggles CloudKit sync on or off. Persists the preference to UserDefaults.
    /// Stops the heartbeat immediately when sync is disabled; re-enabling sync
    /// does not restart the heartbeat (a new `startHeartbeat` call is needed).
    ///
    /// Deliberately does **not** touch `isCloudSyncActive`: the live container keeps
    /// whatever CloudKit mode it launched with until the app is relaunched.
    func setSyncEnabled(_ enabled: Bool) {
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
        if !enabled {
            stopHeartbeat()
        }
    }

    /// Records the CloudKit mode the live `ModelContainer` was actually created with.
    ///
    /// `makeModelConfiguration` calls this for the normal launch path. Launch paths that
    /// bypass it — the unit-test host and UI-test scenarios, which always build an
    /// in-memory, CloudKit-free container — must call it with `false` so display-ID
    /// allocation is gated correctly (T-1797).
    func recordActiveCloudSync(_ active: Bool) {
        isCloudSyncActive = active
    }

    /// Creates a ModelConfiguration based on the current sync preference, and records
    /// that mode as the active one.
    func makeModelConfiguration(schema: Schema) -> ModelConfiguration {
        recordActiveCloudSync(isSyncEnabled)
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
    ///
    /// Gated on the *active* mode, not the preference: pushing a schema to CloudKit for
    /// a container that was built with `cloudKitDatabase: .none` would be reaching into
    /// CloudKit while sync is off (T-1797).
    func initializeCloudKitSchemaIfNeeded(container: ModelContainer) {
        guard isCloudSyncActive else { return }

        // Access the underlying Core Data stack to initialize the CloudKit schema.
        // This is a no-op if the schema is already up to date.
        do {
            try container.mainContext.save()
        } catch {
            // Schema initialization failures are non-fatal — sync will retry.
        }
    }
}
