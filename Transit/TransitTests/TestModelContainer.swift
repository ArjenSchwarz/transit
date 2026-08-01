import Foundation
import SwiftData
@testable import Transit

/// Owns an isolated in-memory ModelContainer and its ModelContext for tests.
///
/// Construct this fixture at the test boundary instead of returning a bare
/// ModelContext from helper functions. Every container is retained centrally,
/// including custom-schema fixtures used by multi-context tests, so no public
/// raw-container factory can bypass the ownership guarantee.
@MainActor
struct TestModelContainer {
    let container: ModelContainer
    let context: ModelContext

    // Intentionally retained for the test process lifetime. Do not clear this
    // while escaped contexts may still be in use; bounded test-only memory is
    // the tradeoff that makes accidental temporary fixture extraction safe.
    private static var retainedContainers: [ModelContainer] = []

    init() throws {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self])
        let config = ModelConfiguration(
            "TransitTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        try self.init(schema: schema, configurations: [config])
    }

    /// Creates a retained fixture for tests that need a custom schema or
    /// multiple contexts sharing one store.
    init(schema: Schema, configurations: [ModelConfiguration]) throws {
        let container = try ModelContainer(for: schema, configurations: configurations)
        self.container = container
        self.context = ModelContext(container)
        Self.retainedContainers.append(container)
    }

    /// Performs a rollback and forces re-faulting of all @Model objects.
    ///
    /// Delegates to the production `ModelContext.safeRollback()` extension.
    /// Kept as a static helper so existing tests don't need to change their
    /// call sites.
    static func rollback(_ context: ModelContext) {
        context.safeRollback()
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
    private var loadCount: Int = 0

    init(initialNextDisplayID: Int = 1) {
        self.nextDisplayID = initialNextDisplayID
    }

    var saveAttemptCount: Int {
        attemptCount
    }

    /// Number of `loadCounter` calls. Together with `saveAttemptCount` this proves
    /// whether the counter store was reached at all — the core assertion for T-1797.
    var loadAttemptCount: Int {
        loadCount
    }

    /// True when neither `loadCounter` nor `saveCounter` has ever been called.
    var wasNeverAccessed: Bool {
        loadCount == 0 && attemptCount == 0
    }

    func enqueueSaveOutcomes(_ outcomes: [SaveOutcome]) {
        pendingSaveOutcomes.append(contentsOf: outcomes)
    }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        loadCount += 1
        return DisplayIDAllocator.CounterSnapshot(
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
