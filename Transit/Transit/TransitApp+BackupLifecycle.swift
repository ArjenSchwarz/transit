import SwiftData

extension TransitApp {
    #if os(macOS)
    static func installBackupMaintenance(container: ModelContainer,
                                         syncManager: SyncManager, connectivityMonitor: ConnectivityMonitor,
                                         server: MCPServer, coordinator: MCPWriteCoordinator) {
        guard !AppPersistencePolicy.current.usesMemoryStore else { return }
        DatabaseMaintenanceGate.shared.install(container: container,
            prepare: { try coordinator.databaseReplacementSnapshot() },
            authorize: { _ = try coordinator.databaseReplacementSnapshot(requireQuiescent: true) },
            finish: {
                server.stop()
                syncManager.stopHeartbeat()
                connectivityMonitor.stop()
                try coordinator.finishDatabaseReplacement()
            })
    }
    #else
    static func installBackupMaintenance(container: ModelContainer,
                                         syncManager: SyncManager, connectivityMonitor: ConnectivityMonitor) {
        guard !AppPersistencePolicy.current.usesMemoryStore else { return }
        DatabaseMaintenanceGate.shared.install(container: container, prepare: { [] }, finish: {
            syncManager.stopHeartbeat()
            connectivityMonitor.stop()
        })
    }
    #endif
}
