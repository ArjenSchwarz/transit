import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DashboardLogicTests {
    @Test
    func filteredColumnsApplies48HourCutoffAndKeepsTerminalTasksWithNilCompletionDateVisible() throws {
        let context = try makeModelContext()
        let project = Project(name: "Transit", description: "Core", color: .blue)
        context.insert(project)

        let now = Date(timeIntervalSince1970: 1_000_000)

        let recentDone = makeTask(
            name: "Recent done",
            status: .done,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-1_200),
            completionDate: now.addingTimeInterval(-1_200)
        )
        let oldDone = makeTask(
            name: "Old done",
            status: .done,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-300_000),
            completionDate: now.addingTimeInterval(-(Date.fortyEightHours + 1))
        )
        let terminalWithoutCompletion = makeTask(
            name: "Defensive terminal",
            status: .abandoned,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-500),
            completionDate: nil
        )

        [recentDone, oldDone, terminalWithoutCompletion].forEach(context.insert)

        let columns = DashboardLogic.filteredColumns(
            tasks: [recentDone, oldDone, terminalWithoutCompletion],
            selectedProjectIDs: [],
            now: now
        )
        let terminalTasks = columns[.doneAbandoned] ?? []

        #expect(terminalTasks.map(\.name) == ["Recent done", "Defensive terminal"])
    }

    @Test
    func filteredColumnsSortsHandoffFirstThenByDateAndPlacesDoneBeforeAbandoned() throws {
        let context = try makeModelContext()
        let project = Project(name: "Transit", description: "Core", color: .blue)
        context.insert(project)

        let now = Date(timeIntervalSince1970: 2_000_000)

        let handoff = makeTask(
            name: "Ready handoff",
            status: .readyForImplementation,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-10_000)
        )
        let regularNewer = makeTask(
            name: "Regular newer",
            status: .spec,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-100)
        )
        let regularOlder = makeTask(
            name: "Regular older",
            status: .spec,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-20_000)
        )

        let abandonedNewest = makeTask(
            name: "Abandoned newest",
            status: .abandoned,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-50),
            completionDate: now.addingTimeInterval(-50)
        )
        let doneOlder = makeTask(
            name: "Done older",
            status: .done,
            project: project,
            lastStatusChangeDate: now.addingTimeInterval(-500),
            completionDate: now.addingTimeInterval(-500)
        )

        let tasks = [handoff, regularNewer, regularOlder, abandonedNewest, doneOlder]
        tasks.forEach(context.insert)

        let columns = DashboardLogic.filteredColumns(tasks: tasks, selectedProjectIDs: [], now: now)

        #expect((columns[.spec] ?? []).map(\.name) == ["Ready handoff", "Regular newer", "Regular older"])
        #expect((columns[.doneAbandoned] ?? []).map(\.name) == ["Done older", "Abandoned newest"])
    }

    @Test
    func filteredColumnsAppliesProjectFilterAndExcludesTasksWithoutProject() throws {
        let context = try makeModelContext()
        let projectA = Project(name: "A", description: "A", color: .blue)
        let projectB = Project(name: "B", description: "B", color: .green)
        context.insert(projectA)
        context.insert(projectB)

        let now = Date(timeIntervalSince1970: 3_000_000)

        let aTask = makeTask(name: "A task", status: .idea, project: projectA, lastStatusChangeDate: now)
        let bTask = makeTask(name: "B task", status: .planning, project: projectB, lastStatusChangeDate: now)
        let orphanTask = makeTask(name: "Orphan", status: .idea, project: nil, lastStatusChangeDate: now)

        let tasks = [aTask, bTask, orphanTask]
        tasks.forEach(context.insert)

        let unfiltered = DashboardLogic.filteredColumns(tasks: tasks, selectedProjectIDs: [], now: now)
        #expect((unfiltered[.idea] ?? []).map(\.name) == ["A task"])
        #expect((unfiltered[.planning] ?? []).map(\.name) == ["B task"])

        let filtered = DashboardLogic.filteredColumns(tasks: tasks, selectedProjectIDs: [projectA.id], now: now)
        #expect((filtered[.idea] ?? []).map(\.name) == ["A task"])
        #expect((filtered[.planning] ?? []).isEmpty)
    }

    @Test
    func filteredColumnsCountsIncludeHandoffStatusesInParentColumns() throws {
        let context = try makeModelContext()
        let project = Project(name: "Transit", description: "Core", color: .blue)
        context.insert(project)

        let now = Date(timeIntervalSince1970: 4_000_000)

        let spec = makeTask(name: "Spec", status: .spec, project: project, lastStatusChangeDate: now)
        let readyForImplementation = makeTask(
            name: "RFI",
            status: .readyForImplementation,
            project: project,
            lastStatusChangeDate: now
        )
        let inProgress = makeTask(name: "In progress", status: .inProgress, project: project, lastStatusChangeDate: now)
        let readyForReview = makeTask(name: "RFR", status: .readyForReview, project: project, lastStatusChangeDate: now)

        let tasks = [spec, readyForImplementation, inProgress, readyForReview]
        tasks.forEach(context.insert)

        let columns = DashboardLogic.filteredColumns(tasks: tasks, selectedProjectIDs: [], now: now)

        #expect((columns[.spec] ?? []).count == 2)
        #expect((columns[.inProgress] ?? []).count == 2)
    }

    @Test
    func applyDropMapsEveryColumnToPrimaryStatusAndNeverUsesAbandoned() async throws {
        let (context, service) = try await makeTaskService()
        let project = Project(name: "Transit", description: "Core", color: .blue)
        context.insert(project)

        let now = Date(timeIntervalSince1970: 5_000_000)

        for column in DashboardColumn.allCases {
            let task = makeTask(
                name: "Task \(column.rawValue)",
                status: .abandoned,
                project: project,
                lastStatusChangeDate: now,
                completionDate: now
            )
            context.insert(task)

            try DashboardLogic.applyDrop(task: task, to: column, using: service, now: now.addingTimeInterval(1))
            #expect(task.status == column.primaryStatus)
            #expect(task.status != .abandoned)
        }
    }

    @Test
    func applyDropSupportsBackwardDragAndClearsCompletionDateWhenLeavingTerminalStatus() async throws {
        let (context, service) = try await makeTaskService()
        let project = Project(name: "Transit", description: "Core", color: .blue)
        context.insert(project)

        let now = Date(timeIntervalSince1970: 6_000_000)

        let activeTask = makeTask(
            name: "Active",
            status: .inProgress,
            project: project,
            lastStatusChangeDate: now
        )
        context.insert(activeTask)

        try DashboardLogic.applyDrop(task: activeTask, to: .planning, using: service, now: now.addingTimeInterval(5))
        #expect(activeTask.status == .planning)

        let doneTask = makeTask(
            name: "Done",
            status: .done,
            project: project,
            lastStatusChangeDate: now,
            completionDate: now
        )
        context.insert(doneTask)

        try DashboardLogic.applyDrop(task: doneTask, to: .spec, using: service, now: now.addingTimeInterval(10))
        #expect(doneTask.status == .spec)
        #expect(doneTask.completionDate == nil)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try makeInMemoryModelContainer()
        return ModelContext(container)
    }

    private func makeTask(
        name: String,
        status: TaskStatus,
        project: Project?,
        lastStatusChangeDate: Date,
        completionDate: Date? = nil
    ) -> TransitTask {
        TransitTask(
            name: name,
            status: status,
            type: .feature,
            creationDate: lastStatusChangeDate,
            lastStatusChangeDate: lastStatusChangeDate,
            completionDate: completionDate,
            project: project
        )
    }

    private func makeTaskService() async throws -> (ModelContext, TaskService) {
        let context = try makeModelContext()
        let counterStore = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: counterStore)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (context, service)
    }
}
