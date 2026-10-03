import Foundation
import SwiftData

/// Opt-in test-host attestation; preflight runs before ModelContainer creation.
enum AppIsolationSmoke {
    struct Snapshot {
        let mode: AppPersistencePolicy.Mode
        let storeURL: URL
        let memoryOnly: Bool
        let cloudSyncActive: Bool
        let disabledCounters: Bool
        let sidecar: URL
    }

    static var snapshot: Snapshot?
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TRANSIT_ISOLATION_SMOKE"] == "1"
    }

    static func preflight(mode: AppPersistencePolicy.Mode, configuration: ModelConfiguration) {
        guard enabled else { return }
        let environment = ProcessInfo.processInfo.environment
        precondition(environment["TRANSIT_PERSISTENCE_MODE"] == "unit-test")
        precondition(mode == .unitTest && Bundle.main.bundleIdentifier == AppPersistencePolicy.developmentBundleID)
        precondition(environment["TRANSIT_SMOKE_HOST_PATH"] == Bundle.main.bundleURL.path)
        precondition(configuration.isStoredInMemoryOnly)
        precondition(configuration.cloudKitContainerIdentifier == nil)
        precondition(configuration.groupAppContainerIdentifier == nil)
        precondition(!configuration.url.path.contains("me.nore.ig.Transit/"))
    }

    static func record(
        mode: AppPersistencePolicy.Mode, container: ModelContainer, cloudSyncActive: Bool,
        allocators: AppDisplayIDAllocators.Pair, sidecar: URL
    ) {
        guard enabled else { return }
        precondition(!cloudSyncActive && !mode.permitsAutomaticMCPStartup)
        precondition(container.configurations.allSatisfy {
            $0.isStoredInMemoryOnly && $0.cloudKitContainerIdentifier == nil
                && $0.groupAppContainerIdentifier == nil
        })
        let disabled = [allocators.tasks, allocators.milestones].allSatisfy {
            !$0.isCloudSyncActive && $0.counterStore is DisabledCounterStore
        }
        precondition(disabled)
        precondition(sidecar.deletingLastPathComponent() == FileManager.default.temporaryDirectory)
        precondition(sidecar.lastPathComponent.hasPrefix("mcp-tests-"))
        snapshot = Snapshot(mode: mode, storeURL: container.configurations.first!.url,
                            memoryOnly: true, cloudSyncActive: cloudSyncActive,
                            disabledCounters: disabled, sidecar: sidecar)
    }
}
