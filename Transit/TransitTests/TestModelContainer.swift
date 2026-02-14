import Foundation
import SwiftData
@testable import Transit

/// Provides isolated in-memory ModelContexts for tests.
@MainActor
enum TestModelContainer {
    /// Returns a fresh ModelContext backed by its own in-memory container to
    /// avoid cross-test state leakage between suites.
    static func newContext() throws -> ModelContext {
        let schema = Schema([Project.self, TransitTask.self, Comment.self])
        let config = ModelConfiguration(
            "TransitTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}

// MARK: - InMemoryCounterStore

/// An in-memory implementation of `DisplayIDAllocator.CounterStore` for tests.
/// Supports queuing save outcomes to simulate conflicts and failures.
actor InMemoryCounterStore: DisplayIDAllocator.CounterStore {
    enum SaveOutcome {
        case success
        case conflict
        case failure(Swift.Error)
    }

    private var nextDisplayID: Int
    private var changeTag: Int = 0
    private var pendingSaveOutcomes: [SaveOutcome] = []
    private var attemptCount: Int = 0

    init(initialNextDisplayID: Int = 1) {
        self.nextDisplayID = initialNextDisplayID
    }

    var saveAttemptCount: Int {
        attemptCount
    }

    func enqueueSaveOutcomes(_ outcomes: [SaveOutcome]) {
        pendingSaveOutcomes.append(contentsOf: outcomes)
    }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        DisplayIDAllocator.CounterSnapshot(
            nextDisplayID: nextDisplayID,
            changeTag: "\(changeTag)"
        )
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        attemptCount += 1

        guard expectedChangeTag == "\(changeTag)" else {
            throw DisplayIDAllocator.Error.conflict
        }

        if !pendingSaveOutcomes.isEmpty {
            let outcome = pendingSaveOutcomes.removeFirst()
            switch outcome {
            case .success:
                self.nextDisplayID = nextDisplayID
                changeTag += 1
                return
            case .conflict:
                changeTag += 1
                throw DisplayIDAllocator.Error.conflict
            case .failure(let error):
                throw error
            }
        }

        self.nextDisplayID = nextDisplayID
        changeTag += 1
    }
}
