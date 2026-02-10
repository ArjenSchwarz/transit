import Foundation
import Testing
@testable import Transit

@MainActor
struct StatusEngineTests {
    @Test
    func initializeNewTaskSetsIdeaAndTimestamps() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let task = TransitTask(name: "Status init")

        StatusEngine.initializeNewTask(task, now: now)

        #expect(task.status == .idea)
        #expect(task.creationDate == now)
        #expect(task.lastStatusChangeDate == now)
        #expect(task.completionDate == nil)
    }

    @Test
    func transitionToTerminalSetsCompletionDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let task = TransitTask(name: "Terminal", status: .inProgress, completionDate: nil)

        StatusEngine.applyTransition(task: task, to: .done, now: now)

        #expect(task.status == .done)
        #expect(task.lastStatusChangeDate == now)
        #expect(task.completionDate == now)
    }

    @Test
    func transitionFromTerminalToActiveClearsCompletionDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_200)
        let previousDate = Date(timeIntervalSince1970: 1_700_000_150)
        let task = TransitTask(name: "Restore", status: .abandoned, completionDate: previousDate)

        StatusEngine.applyTransition(task: task, to: .planning, now: now)

        #expect(task.status == .planning)
        #expect(task.lastStatusChangeDate == now)
        #expect(task.completionDate == nil)
    }

    @Test
    func propertyBasedTransitionInvariantsHold() {
        var generator = SeededGenerator(seed: 42)

        for index in 0..<512 {
            let oldStatus = TaskStatus.allCases.randomElement(using: &generator) ?? .idea
            let newStatus = TaskStatus.allCases.randomElement(using: &generator) ?? .idea
            let baseTime = Date(timeIntervalSince1970: TimeInterval(1_700_100_000 + index))
            let existingCompletionDate = generator.nextBool() ? baseTime.addingTimeInterval(-60) : nil

            let task = TransitTask(
                name: "Task \(index)",
                status: oldStatus,
                completionDate: existingCompletionDate
            )

            StatusEngine.applyTransition(task: task, to: newStatus, now: baseTime)

            #expect(task.status == newStatus)
            #expect(task.lastStatusChangeDate == baseTime)

            if newStatus.isTerminal {
                #expect(task.completionDate == baseTime)
            } else if oldStatus.isTerminal {
                #expect(task.completionDate == nil)
            } else {
                #expect(task.completionDate == existingCompletionDate)
            }
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextBool() -> Bool {
        (next() & 1) == 1
    }
}
