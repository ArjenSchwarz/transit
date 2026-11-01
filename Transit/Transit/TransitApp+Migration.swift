import SwiftData

extension TransitApp {
    func finishMigrationVerification() {
        guard PersistenceAvailability.shared.migrationRequiresVerification,
              migrationPreflight?.isVerified == true, let floors = migrationPreflight?.verifiedFloors else { return }
        PersistenceAvailability.shared.migrationCounterFloors = (tasks: floors.tasks, milestones: floors.milestones)
        container.mainContext.autosaveEnabled = true
        PersistenceAvailability.shared.setMigrationVerificationRequired(false)
        migrationReady = true
        startVerifiedReleaseServices()
    }

    func startVerifiedReleaseServices() {
        guard Self.persistenceMode == .production, !PersistenceAvailability.shared.areWritesUnavailable else { return }
        syncManager.initializeCloudKitSchemaIfNeeded(container: container)
        TaskLinkEvidenceMaintenance.atStartup(container: container, mode: Self.persistenceMode, persistence: .shared)
        connectivityMonitor.start()
        #if os(macOS)
        try? mcpWriteCoordinator.cleanupExpiredOutcomes()
        #endif
    }
}
