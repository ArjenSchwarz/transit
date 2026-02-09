import Foundation
import Testing
@testable import Transit

@MainActor
struct StatusEngineTests {

    // MARK: - Helpers

    private func makeTask() -> TransitTask {
        let project = Project(name: "Test", description: "Test project", gitRepo: nil, colorHex: "#000000")
        return TransitTask(name: "Test Task", type: .feature, project: project, displayID: .provisional)
    }

    // MARK: - initializeNewTask

    @Test func initializeNewTaskSetsStatusToIdea() {
        let task = makeTask()
        let now = Date(timeIntervalSince1970: 1000)
        StatusEngine.initializeNewTask(task, now: now)

        #expect(task.status == .idea)
    }

    @Test func initializeNewTaskSetsCreationDateAndLastStatusChangeDate() {
        let task = makeTask()
        let now = Date(timeIntervalSince1970: 1000)
        StatusEngine.initializeNewTask(task, now: now)

        #expect(task.creationDate == now)
        #expect(task.lastStatusChangeDate == now)
    }

    // MARK: - Transition to terminal statuses

    @Test func transitionToDoneSetsCompletionDate() {
        let task = makeTask()
        let now = Date(timeIntervalSince1970: 2000)
        StatusEngine.applyTransition(task: task, to: .done, now: now)

        #expect(task.status == .done)
        #expect(task.completionDate == now)
    }

    @Test func transitionToAbandonedSetsCompletionDate() {
        let task = makeTask()
        let now = Date(timeIntervalSince1970: 2000)
        StatusEngine.applyTransition(task: task, to: .abandoned, now: now)

        #expect(task.status == .abandoned)
        #expect(task.completionDate == now)
    }

    // MARK: - lastStatusChangeDate

    @Test func everyTransitionUpdatesLastStatusChangeDate() {
        let task = makeTask()
        let statuses: [TaskStatus] = [.planning, .spec, .readyForImplementation, .inProgress, .readyForReview, .done]

        for (index, status) in statuses.enumerated() {
            let now = Date(timeIntervalSince1970: Double(1000 + index * 100))
            StatusEngine.applyTransition(task: task, to: status, now: now)
            #expect(task.lastStatusChangeDate == now, "lastStatusChangeDate not updated for \(status)")
        }
    }

    // MARK: - Clearing completionDate

    @Test func movingFromDoneToNonTerminalClearsCompletionDate() {
        let task = makeTask()
        StatusEngine.applyTransition(task: task, to: .done, now: Date(timeIntervalSince1970: 1000))
        #expect(task.completionDate != nil)

        StatusEngine.applyTransition(task: task, to: .inProgress, now: Date(timeIntervalSince1970: 2000))
        #expect(task.completionDate == nil)
    }

    @Test func movingFromAbandonedToNonTerminalClearsCompletionDate() {
        let task = makeTask()
        StatusEngine.applyTransition(task: task, to: .abandoned, now: Date(timeIntervalSince1970: 1000))
        #expect(task.completionDate != nil)

        StatusEngine.applyTransition(task: task, to: .planning, now: Date(timeIntervalSince1970: 2000))
        #expect(task.completionDate == nil)
    }

    @Test func movingFromAbandonedToIdeaClearsCompletionDate() {
        let task = makeTask()
        StatusEngine.applyTransition(task: task, to: .abandoned, now: Date(timeIntervalSince1970: 1000))
        #expect(task.completionDate != nil)

        StatusEngine.applyTransition(task: task, to: .idea, now: Date(timeIntervalSince1970: 2000))
        #expect(task.completionDate == nil)
    }

    // MARK: - Non-terminal transitions

    @Test func transitionBetweenNonTerminalStatusesDoesNotSetCompletionDate() {
        let task = makeTask()
        StatusEngine.initializeNewTask(task, now: Date(timeIntervalSince1970: 1000))

        StatusEngine.applyTransition(task: task, to: .planning, now: Date(timeIntervalSince1970: 2000))
        #expect(task.completionDate == nil)

        StatusEngine.applyTransition(task: task, to: .spec, now: Date(timeIntervalSince1970: 3000))
        #expect(task.completionDate == nil)

        StatusEngine.applyTransition(task: task, to: .inProgress, now: Date(timeIntervalSince1970: 4000))
        #expect(task.completionDate == nil)
    }

    // MARK: - Re-abandoning / re-completing

    @Test func reAbandoningDoneTaskOverwritesCompletionDate() {
        let task = makeTask()
        let doneTime = Date(timeIntervalSince1970: 1000)
        StatusEngine.applyTransition(task: task, to: .done, now: doneTime)
        #expect(task.completionDate == doneTime)

        let abandonTime = Date(timeIntervalSince1970: 2000)
        StatusEngine.applyTransition(task: task, to: .abandoned, now: abandonTime)
        #expect(task.completionDate == abandonTime)
    }

    // MARK: - Property-based tests

    @Test func completionDateIsNonNilIffStatusIsTerminalAfterAnyTransitionSequence() {
        let task = makeTask()
        StatusEngine.initializeNewTask(task, now: Date(timeIntervalSince1970: 0))

        let sequence: [TaskStatus] = [
            .planning, .spec, .readyForImplementation, .inProgress,
            .done, .idea, .planning, .abandoned, .idea,
            .spec, .inProgress, .readyForReview, .done,
            .abandoned, .done
        ]

        for (index, status) in sequence.enumerated() {
            let now = Date(timeIntervalSince1970: Double((index + 1) * 100))
            StatusEngine.applyTransition(task: task, to: status, now: now)

            if status.isTerminal {
                #expect(task.completionDate != nil, "completionDate should be set for terminal status \(status)")
            } else {
                #expect(task.completionDate == nil, "completionDate should be nil for non-terminal status \(status)")
            }
        }
    }

    @Test func lastStatusChangeDateIsMonotonicallyNonDecreasingAcrossTransitions() {
        let task = makeTask()
        StatusEngine.initializeNewTask(task, now: Date(timeIntervalSince1970: 0))

        let sequence: [TaskStatus] = [
            .planning, .spec, .inProgress, .done, .idea, .abandoned, .idea, .planning
        ]

        var previousDate = task.lastStatusChangeDate
        for (index, status) in sequence.enumerated() {
            let now = Date(timeIntervalSince1970: Double((index + 1) * 100))
            StatusEngine.applyTransition(task: task, to: status, now: now)

            #expect(task.lastStatusChangeDate >= previousDate,
                    "lastStatusChangeDate decreased at transition to \(status)")
            previousDate = task.lastStatusChangeDate
        }
    }
}
