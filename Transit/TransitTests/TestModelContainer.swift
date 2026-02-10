import SwiftData
@testable import Transit

/// Provides a shared in-memory ModelContainer for tests. Creating multiple
/// ModelContainer instances for the same schema in the same process causes
/// `loadIssueModelContainer` errors. Using a single shared container avoids
/// this while giving each test a fresh ModelContext.
@MainActor
enum TestModelContainer {
    private static var _container: ModelContainer?

    static var shared: ModelContainer {
        get throws {
            if let container = _container {
                return container
            }
            let schema = Schema([Project.self, TransitTask.self])
            let config = ModelConfiguration(
                "TransitTests",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            _container = container
            return container
        }
    }

    /// Returns a fresh ModelContext from the shared container. Each test
    /// should use its own context to avoid cross-test state leakage.
    static func newContext() throws -> ModelContext {
        let container = try shared
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
