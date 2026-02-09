import Testing
@testable import Transit

@MainActor
struct TaskStatusTests {

    // MARK: - Column Mapping

    @Test func ideaMapsToIdeaColumn() {
        #expect(TaskStatus.idea.column == .idea)
    }

    @Test func planningMapsToPlanningColumn() {
        #expect(TaskStatus.planning.column == .planning)
    }

    @Test func specMapsToSpecColumn() {
        #expect(TaskStatus.spec.column == .spec)
    }

    @Test func readyForImplementationMapsToSpecColumn() {
        #expect(TaskStatus.readyForImplementation.column == .spec)
    }

    @Test func inProgressMapsToInProgressColumn() {
        #expect(TaskStatus.inProgress.column == .inProgress)
    }

    @Test func readyForReviewMapsToInProgressColumn() {
        #expect(TaskStatus.readyForReview.column == .inProgress)
    }

    @Test func doneMapsToCompletedColumn() {
        #expect(TaskStatus.done.column == .doneAbandoned)
    }

    @Test func abandonedMapsToCompletedColumn() {
        #expect(TaskStatus.abandoned.column == .doneAbandoned)
    }

    // MARK: - isHandoff

    @Test func readyForImplementationIsHandoff() {
        #expect(TaskStatus.readyForImplementation.isHandoff)
    }

    @Test func readyForReviewIsHandoff() {
        #expect(TaskStatus.readyForReview.isHandoff)
    }

    @Test func nonHandoffStatusesAreNotHandoff() {
        let nonHandoff: [TaskStatus] = [.idea, .planning, .spec, .inProgress, .done, .abandoned]
        for status in nonHandoff {
            #expect(!status.isHandoff, "Expected \(status) to not be handoff")
        }
    }

    // MARK: - isTerminal

    @Test func doneIsTerminal() {
        #expect(TaskStatus.done.isTerminal)
    }

    @Test func abandonedIsTerminal() {
        #expect(TaskStatus.abandoned.isTerminal)
    }

    @Test func nonTerminalStatusesAreNotTerminal() {
        let nonTerminal: [TaskStatus] = [.idea, .planning, .spec, .readyForImplementation, .inProgress, .readyForReview]
        for status in nonTerminal {
            #expect(!status.isTerminal, "Expected \(status) to not be terminal")
        }
    }

    // MARK: - shortLabel

    @Test func shortLabelsMatchSpec() {
        #expect(TaskStatus.idea.shortLabel == "Idea")
        #expect(TaskStatus.planning.shortLabel == "Plan")
        #expect(TaskStatus.spec.shortLabel == "Spec")
        #expect(TaskStatus.readyForImplementation.shortLabel == "Spec")
        #expect(TaskStatus.inProgress.shortLabel == "Active")
        #expect(TaskStatus.readyForReview.shortLabel == "Active")
        #expect(TaskStatus.done.shortLabel == "Done")
        #expect(TaskStatus.abandoned.shortLabel == "Done")
    }

    // MARK: - DashboardColumn.primaryStatus

    @Test func ideaColumnPrimaryStatusIsIdea() {
        #expect(DashboardColumn.idea.primaryStatus == .idea)
    }

    @Test func planningColumnPrimaryStatusIsPlanning() {
        #expect(DashboardColumn.planning.primaryStatus == .planning)
    }

    @Test func specColumnPrimaryStatusIsSpec() {
        #expect(DashboardColumn.spec.primaryStatus == .spec)
    }

    @Test func inProgressColumnPrimaryStatusIsInProgress() {
        #expect(DashboardColumn.inProgress.primaryStatus == .inProgress)
    }

    @Test func doneAbandonedColumnPrimaryStatusIsDone() {
        #expect(DashboardColumn.doneAbandoned.primaryStatus == .done)
    }

    // MARK: - Codable round-trip

    @Test func taskStatusRawValuesAreCorrect() {
        #expect(TaskStatus.readyForImplementation.rawValue == "ready-for-implementation")
        #expect(TaskStatus.inProgress.rawValue == "in-progress")
        #expect(TaskStatus.readyForReview.rawValue == "ready-for-review")
    }
}
