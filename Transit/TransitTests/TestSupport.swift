import SwiftData
@testable import Transit

@MainActor
func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Project.self,
        TransitTask.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

enum MockCounterError: Swift.Error {
    case syntheticFailure
}

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

    init(initialNextDisplayID: Int) {
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
