//
//  TaskStatusTests.swift
//  TransitTests
//
//  Tests for TaskStatus and DashboardColumn enums.
//

import Testing
@testable import Transit

@MainActor
struct TaskStatusTests {
    // MARK: - Column Mapping Tests

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

    @Test func doneMapsToDoneAbandonedColumn() {
        #expect(TaskStatus.done.column == .doneAbandoned)
    }

    @Test func abandonedMapsToDoneAbandonedColumn() {
        #expect(TaskStatus.abandoned.column == .doneAbandoned)
    }

    // MARK: - Handoff Status Tests

    @Test func readyForImplementationIsHandoff() {
        #expect(TaskStatus.readyForImplementation.isHandoff)
    }

    @Test func readyForReviewIsHandoff() {
        #expect(TaskStatus.readyForReview.isHandoff)
    }

    @Test func nonHandoffStatusesAreNotHandoff() {
        let nonHandoffStatuses: [TaskStatus] = [
            .idea, .planning, .spec, .inProgress, .done, .abandoned
        ]
        for status in nonHandoffStatuses {
            #expect(!status.isHandoff)
        }
    }

    // MARK: - Terminal Status Tests

    @Test func doneIsTerminal() {
        #expect(TaskStatus.done.isTerminal)
    }

    @Test func abandonedIsTerminal() {
        #expect(TaskStatus.abandoned.isTerminal)
    }

    @Test func nonTerminalStatusesAreNotTerminal() {
        let nonTerminalStatuses: [TaskStatus] = [
            .idea, .planning, .spec, .readyForImplementation,
            .inProgress, .readyForReview
        ]
        for status in nonTerminalStatuses {
            #expect(!status.isTerminal)
        }
    }

    // MARK: - Short Label Tests

    @Test func shortLabels() {
        #expect(TaskStatus.idea.shortLabel == "Idea")
        #expect(TaskStatus.planning.shortLabel == "Plan")
        #expect(TaskStatus.spec.shortLabel == "Spec")
        #expect(TaskStatus.readyForImplementation.shortLabel == "Spec")
        #expect(TaskStatus.inProgress.shortLabel == "Active")
        #expect(TaskStatus.readyForReview.shortLabel == "Active")
        #expect(TaskStatus.done.shortLabel == "Done")
        #expect(TaskStatus.abandoned.shortLabel == "Done")
    }

    // MARK: - DashboardColumn Primary Status Tests

    @Test func columnPrimaryStatuses() {
        #expect(DashboardColumn.idea.primaryStatus == .idea)
        #expect(DashboardColumn.planning.primaryStatus == .planning)
        #expect(DashboardColumn.spec.primaryStatus == .spec)
        #expect(DashboardColumn.inProgress.primaryStatus == .inProgress)
        #expect(DashboardColumn.doneAbandoned.primaryStatus == .done)
    }

    @Test func columnDisplayNames() {
        #expect(DashboardColumn.idea.displayName == "Idea")
        #expect(DashboardColumn.planning.displayName == "Planning")
        #expect(DashboardColumn.spec.displayName == "Spec")
        #expect(DashboardColumn.inProgress.displayName == "In Progress")
        #expect(DashboardColumn.doneAbandoned.displayName == "Done / Abandoned")
    }
}
