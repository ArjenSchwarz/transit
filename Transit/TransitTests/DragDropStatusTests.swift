import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct DragDropStatusTests {

    // MARK: - Helpers

    private func makeTask(status: TaskStatus = .idea) -> TransitTask {
        let project = Project(name: "Test", description: "Desc", gitRepo: nil, colorHex: "FF0000")
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)
        task.statusRawValue = status.rawValue
        return task
    }

    /// Creates a TaskService backed by an in-memory SwiftData context and inserts
    /// a task with the given status. Returns both so the caller can assert on the task.
    private func makeServiceAndTask(
        status: TaskStatus
    ) throws -> (service: TaskService, task: TransitTask) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "Test", description: "Desc", gitRepo: nil, colorHex: "FF0000")
        context.insert(project)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)
        task.statusRawValue = status.rawValue
        context.insert(task)
        try context.save()

        return (service, task)
    }

    /// Simulates a drag-and-drop by applying the column's primaryStatus via StatusEngine.
    private func simulateDrop(task: TransitTask, to column: DashboardColumn) {
        StatusEngine.applyTransition(task: task, to: column.primaryStatus)
    }

    // MARK: - Base status per column [req 7.1]

    @Test func droppingOnIdeaColumnSetsIdea() {
        let task = makeTask(status: .inProgress)
        simulateDrop(task: task, to: .idea)
        #expect(task.status == .idea)
    }

    @Test func droppingOnPlanningColumnSetsPlanningStatus() {
        let task = makeTask(status: .idea)
        simulateDrop(task: task, to: .planning)
        #expect(task.status == .planning)
    }

    @Test func droppingOnSpecColumnSetsSpecNotReadyForImplementation() {
        let task = makeTask(status: .idea)
        simulateDrop(task: task, to: .spec)
        #expect(task.status == .spec)
        #expect(task.status != .readyForImplementation)
    }

    @Test func droppingOnInProgressColumnSetsInProgressNotReadyForReview() {
        let task = makeTask(status: .spec)
        simulateDrop(task: task, to: .inProgress)
        #expect(task.status == .inProgress)
        #expect(task.status != .readyForReview)
    }

    // MARK: - Done/Abandoned column [req 7.2, 7.4]

    @Test func droppingOnDoneAbandonedColumnSetsDone() {
        let task = makeTask(status: .inProgress)
        simulateDrop(task: task, to: .doneAbandoned)
        #expect(task.status == .done)
    }

    @Test func droppingOnDoneAbandonedColumnNeverSetsAbandoned() {
        let task = makeTask(status: .inProgress)
        simulateDrop(task: task, to: .doneAbandoned)
        #expect(task.status != .abandoned)
    }

    // MARK: - Backward drag [req 7.1]

    @Test func backwardDragFromInProgressToPlanning() {
        let task = makeTask(status: .inProgress)
        simulateDrop(task: task, to: .planning)
        #expect(task.status == .planning)
    }

    // MARK: - Completion date handling [req 7.5]

    @Test func droppingDoneTaskOnNonTerminalColumnClearsCompletionDate() {
        let task = makeTask(status: .done)
        task.completionDate = Date(timeIntervalSince1970: 1000)

        simulateDrop(task: task, to: .inProgress)
        #expect(task.completionDate == nil)
    }

    @Test func droppingOnDoneAbandonedColumnSetsCompletionDate() {
        let task = makeTask(status: .inProgress)
        #expect(task.completionDate == nil)

        simulateDrop(task: task, to: .doneAbandoned)
        #expect(task.completionDate != nil)
    }

    // MARK: - primaryStatus mapping verification

    @Test func primaryStatusMappingIsCorrectForAllColumns() {
        #expect(DashboardColumn.idea.primaryStatus == .idea)
        #expect(DashboardColumn.planning.primaryStatus == .planning)
        #expect(DashboardColumn.spec.primaryStatus == .spec)
        #expect(DashboardColumn.inProgress.primaryStatus == .inProgress)
        #expect(DashboardColumn.doneAbandoned.primaryStatus == .done)
    }

    // MARK: - Regression: drop accepted for every column from every source status

    @Test(
        "Drop succeeds for all column targets regardless of source status",
        arguments: DashboardColumn.allCases
    )
    func dropAcceptedForAllColumns(targetColumn: DashboardColumn) {
        // Start from inProgress so the task is in a mid-workflow state
        let task = makeTask(status: .inProgress)
        simulateDrop(task: task, to: targetColumn)
        #expect(task.status == targetColumn.primaryStatus)
    }

    // MARK: - Regression T-192: same-column drops must be no-ops

    @Test("Abandoned task dropped on Done/Abandoned column stays abandoned")
    func abandonedTaskDroppedOnSameColumnStaysAbandoned() {
        let task = makeTask(status: .abandoned)
        #expect(!DashboardLogic.shouldApplyDrop(task: task, to: .doneAbandoned))
    }

    @Test("Done task dropped on Done/Abandoned column is a no-op")
    func doneTaskDroppedOnSameColumnIsNoOp() {
        let task = makeTask(status: .done)
        #expect(!DashboardLogic.shouldApplyDrop(task: task, to: .doneAbandoned))
    }

    @Test(
        "Same-column drop is always a no-op for every status",
        arguments: TaskStatus.allCases
    )
    func sameColumnDropIsNoOp(status: TaskStatus) {
        let task = makeTask(status: status)
        let originalDate = Date(timeIntervalSince1970: 5000)
        task.lastStatusChangeDate = originalDate

        let column = status.column
        #expect(
            !DashboardLogic.shouldApplyDrop(task: task, to: column),
            "Drop onto the same column (\(column)) should be a no-op for status \(status)"
        )
    }

    @Test("Handoff status is preserved when dropped on its own column")
    func handoffStatusPreservedOnSameColumnDrop() {
        let readyForImpl = makeTask(status: .readyForImplementation)
        #expect(!DashboardLogic.shouldApplyDrop(task: readyForImpl, to: .spec))

        let readyForReview = makeTask(status: .readyForReview)
        #expect(!DashboardLogic.shouldApplyDrop(task: readyForReview, to: .inProgress))
    }

    @Test("Cross-column drop is still applied")
    func crossColumnDropIsApplied() {
        let task = makeTask(status: .inProgress)
        #expect(DashboardLogic.shouldApplyDrop(task: task, to: .doneAbandoned))
        #expect(DashboardLogic.shouldApplyDrop(task: task, to: .planning))
    }

    // MARK: - Integration: applyDrop end-to-end [T-192]

    @Test("applyDrop is a no-op for same-column abandoned task")
    func applyDropSameColumnAbandonedIsNoOp() throws {
        let (service, task) = try makeServiceAndTask(status: .abandoned)
        let originalCompletionDate = Date(timeIntervalSince1970: 1000)
        let originalStatusDate = Date(timeIntervalSince1970: 1000)
        task.completionDate = originalCompletionDate
        task.lastStatusChangeDate = originalStatusDate

        try DashboardLogic.applyDrop(task: task, to: .doneAbandoned, using: service)

        #expect(task.status == .abandoned)
        #expect(task.completionDate == originalCompletionDate)
        #expect(task.lastStatusChangeDate == originalStatusDate)
    }

    @Test("applyDrop is a no-op for same-column done task")
    func applyDropSameColumnDoneIsNoOp() throws {
        let (service, task) = try makeServiceAndTask(status: .done)
        let originalCompletionDate = Date(timeIntervalSince1970: 1000)
        let originalStatusDate = Date(timeIntervalSince1970: 1000)
        task.completionDate = originalCompletionDate
        task.lastStatusChangeDate = originalStatusDate

        try DashboardLogic.applyDrop(task: task, to: .doneAbandoned, using: service)

        #expect(task.status == .done)
        #expect(task.completionDate == originalCompletionDate)
        #expect(task.lastStatusChangeDate == originalStatusDate)
    }

    @Test("applyDrop still applies cross-column drop")
    func applyDropCrossColumnWorks() throws {
        let (service, task) = try makeServiceAndTask(status: .inProgress)
        #expect(task.completionDate == nil)

        try DashboardLogic.applyDrop(task: task, to: .doneAbandoned, using: service)

        #expect(task.status == .done)
        #expect(task.completionDate != nil)
    }
}
