import Testing
@testable import Transit

struct TaskStatusTests {
    @Test
    func taskStatusMapsToExpectedDashboardColumn() {
        #expect(TaskStatus.idea.column == .idea)
        #expect(TaskStatus.planning.column == .planning)
        #expect(TaskStatus.spec.column == .spec)
        #expect(TaskStatus.readyForImplementation.column == .spec)
        #expect(TaskStatus.inProgress.column == .inProgress)
        #expect(TaskStatus.readyForReview.column == .inProgress)
        #expect(TaskStatus.done.column == .doneAbandoned)
        #expect(TaskStatus.abandoned.column == .doneAbandoned)
    }

    @Test
    func handoffStatusesAreExplicit() {
        #expect(TaskStatus.readyForImplementation.isHandoff)
        #expect(TaskStatus.readyForReview.isHandoff)
        #expect(!TaskStatus.idea.isHandoff)
        #expect(!TaskStatus.inProgress.isHandoff)
    }

    @Test
    func terminalStatusesAreDoneAndAbandonedOnly() {
        #expect(TaskStatus.done.isTerminal)
        #expect(TaskStatus.abandoned.isTerminal)
        #expect(!TaskStatus.spec.isTerminal)
        #expect(!TaskStatus.readyForReview.isTerminal)
    }

    @Test
    func shortLabelsMatchSegmentedControlDesign() {
        #expect(TaskStatus.idea.shortLabel == "Idea")
        #expect(TaskStatus.planning.shortLabel == "Plan")
        #expect(TaskStatus.spec.shortLabel == "Spec")
        #expect(TaskStatus.readyForImplementation.shortLabel == "Spec")
        #expect(TaskStatus.inProgress.shortLabel == "Active")
        #expect(TaskStatus.readyForReview.shortLabel == "Active")
        #expect(TaskStatus.done.shortLabel == "Done")
        #expect(TaskStatus.abandoned.shortLabel == "Done")
    }

    @Test
    func dashboardColumnPrimaryStatusUsesBaseDragTargets() {
        #expect(DashboardColumn.idea.primaryStatus == .idea)
        #expect(DashboardColumn.planning.primaryStatus == .planning)
        #expect(DashboardColumn.spec.primaryStatus == .spec)
        #expect(DashboardColumn.inProgress.primaryStatus == .inProgress)
        #expect(DashboardColumn.doneAbandoned.primaryStatus == .done)
    }
}
