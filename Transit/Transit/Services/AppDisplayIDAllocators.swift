import CloudKit
import Foundation

/// Selects counter adapters before any CloudKit container is constructed.
enum AppDisplayIDAllocators {
    struct Pair {
        let tasks: DisplayIDAllocator
        let milestones: DisplayIDAllocator
    }

    static func make(
        mode: AppPersistencePolicy.Mode,
        syncActive: Bool,
        cloudFactory: (String, String) -> DisplayIDAllocator = {
            DisplayIDAllocator(container: CKContainer(identifier: $1), counterRecordName: $0, isCloudSyncActive: true)
        }
    ) -> Pair {
        guard mode.permitsCloudSync && syncActive else {
            return Pair(
                tasks: DisplayIDAllocator(store: DisabledCounterStore(), isCloudSyncActive: false),
                milestones: DisplayIDAllocator(store: DisabledCounterStore(), isCloudSyncActive: false)
            )
        }
        return Pair(tasks: cloudFactory("global-counter", mode.cloudKitContainerID),
                    milestones: cloudFactory("milestone-counter", mode.cloudKitContainerID))
    }
}

/// Fails closed even if a caller bypasses the allocator's inactive-sync guard.
nonisolated struct DisabledCounterStore: DisplayIDAllocator.CounterStore {
    enum Failure: Swift.Error { case unavailable }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        throw Failure.unavailable
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        throw Failure.unavailable
    }
}
