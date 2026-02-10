import Foundation
import Testing
@testable import Transit

@MainActor
struct DashboardFilterTests {

    // MARK: - Helpers

    private func makeProject(name: String = "Test", colorHex: String = "FF0000") -> Project {
        Project(name: name, description: "Description", gitRepo: nil, colorHex: colorHex)
    }

    private func makeTask(
        name: String = "Task",
        status: TaskStatus = .idea,
        type: TaskType = .feature,
        project: Project,
        lastStatusChange: Date = .now,
        completionDate: Date? = nil
    ) -> TransitTask {
        let task = TransitTask(name: name, type: type, project: project, displayID: .provisional)
        task.statusRawValue = status.rawValue
        task.lastStatusChangeDate = lastStatusChange
        task.completionDate = completionDate
        return task
    }

    // MARK: - 48-hour cutoff [req 5.6]

    @Test func doneTasksOlderThan48HoursAreExcluded() {
        let project = makeProject()
        let now = Date(timeIntervalSince1970: 200_000)
        let oldDate = now.addingTimeInterval(-49 * 60 * 60)
        let recentDate = now.addingTimeInterval(-47 * 60 * 60)

        let oldTask = makeTask(name: "Old", status: .done, project: project, completionDate: oldDate)
        let recentTask = makeTask(name: "Recent", status: .done, project: project, completionDate: recentDate)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [oldTask, recentTask],
            selectedProjectIDs: [],
            now: now
        )

        let doneTasks = columns[.doneAbandoned] ?? []
        #expect(doneTasks.count == 1)
        #expect(doneTasks[0].name == "Recent")
    }

    @Test func terminalTaskWithNilCompletionDateShowsDefensively() {
        let project = makeProject()
        let now = Date(timeIntervalSince1970: 200_000)
        let task = makeTask(status: .done, project: project, completionDate: nil)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task],
            selectedProjectIDs: [],
            now: now
        )

        let doneTasks = columns[.doneAbandoned] ?? []
        #expect(doneTasks.count == 1)
    }

    // MARK: - Sorting [req 5.3, 5.4, 5.5, 5.8]

    @Test func handoffTasksSortBeforeRegularTasksInColumn() {
        let project = makeProject()
        let now = Date(timeIntervalSince1970: 200_000)
        let specTask = makeTask(name: "Spec", status: .spec, project: project, lastStatusChange: now)
        let handoffTask = makeTask(
            name: "ReadyForImpl",
            status: .readyForImplementation,
            project: project,
            lastStatusChange: now.addingTimeInterval(-100) // older but handoff
        )

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [specTask, handoffTask],
            selectedProjectIDs: [],
            now: now
        )

        let specColumn = columns[.spec] ?? []
        #expect(specColumn.count == 2)
        #expect(specColumn[0].name == "ReadyForImpl") // Handoff sorts first
        #expect(specColumn[1].name == "Spec")
    }

    @Test func doneTasksSortBeforeAbandonedInTerminalColumn() {
        let project = makeProject()
        let now = Date(timeIntervalSince1970: 200_000)
        let doneTask = makeTask(
            name: "Done",
            status: .done,
            project: project,
            lastStatusChange: now.addingTimeInterval(-100),
            completionDate: now.addingTimeInterval(-100)
        )
        let abandonedTask = makeTask(
            name: "Abandoned",
            status: .abandoned,
            project: project,
            lastStatusChange: now, // more recent but abandoned
            completionDate: now
        )

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [abandonedTask, doneTask],
            selectedProjectIDs: [],
            now: now
        )

        let terminalTasks = columns[.doneAbandoned] ?? []
        #expect(terminalTasks.count == 2)
        #expect(terminalTasks[0].name == "Done")
        #expect(terminalTasks[1].name == "Abandoned")
    }

    @Test func tasksWithinColumnSortByLastStatusChangeDateDescending() {
        let project = makeProject()
        let now = Date(timeIntervalSince1970: 200_000)
        let olderDate = now.addingTimeInterval(-200)
        let older = makeTask(name: "Older", status: .idea, project: project, lastStatusChange: olderDate)
        let newer = makeTask(name: "Newer", status: .idea, project: project, lastStatusChange: now)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [older, newer],
            selectedProjectIDs: [],
            now: now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 2)
        #expect(ideaTasks[0].name == "Newer")
        #expect(ideaTasks[1].name == "Older")
    }

    // MARK: - Project filter [req 9.2]

    @Test func projectFilterReducesToSelectedProjects() {
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let taskA = makeTask(name: "Task A", status: .idea, project: projectA)
        let taskB = makeTask(name: "Task B", status: .idea, project: projectB)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [taskA, taskB],
            selectedProjectIDs: [projectA.id],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Task A")
    }

    @Test func emptyFilterShowsAllTasks() {
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let taskA = makeTask(name: "Task A", status: .idea, project: projectA)
        let taskB = makeTask(name: "Task B", status: .idea, project: projectB)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [taskA, taskB],
            selectedProjectIDs: [],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 2)
    }

    @Test func tasksWithNilProjectAreExcluded() {
        let project = makeProject()
        let taskWithProject = makeTask(name: "Has Project", status: .idea, project: project)
        let orphanTask = TransitTask(name: "Orphan", type: .feature, project: project, displayID: .provisional)
        orphanTask.project = nil

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [taskWithProject, orphanTask],
            selectedProjectIDs: [],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Has Project")
    }

    // MARK: - Column counts include handoff tasks [req 5.9]

    @Test func columnCountsIncludeHandoffTasks() {
        let project = makeProject()
        let now = Date.now
        let specTask = makeTask(name: "Spec", status: .spec, project: project, lastStatusChange: now)
        let handoffTask = makeTask(
            name: "ReadyForImpl", status: .readyForImplementation, project: project, lastStatusChange: now
        )

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [specTask, handoffTask],
            selectedProjectIDs: [],
            now: now
        )

        #expect((columns[.spec] ?? []).count == 2)
    }

    // MARK: - All columns exist even when empty

    @Test func allColumnsExistEvenWhenEmpty() {
        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [],
            selectedProjectIDs: [],
            now: .now
        )

        for column in DashboardColumn.allCases {
            #expect(columns[column] != nil, "Column \(column) should exist")
            #expect(columns[column]?.isEmpty == true)
        }
    }
}
