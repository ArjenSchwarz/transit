import Foundation
import Testing
@testable import Transit

@MainActor
struct DashboardSearchTests {

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

    // MARK: - Text search filter

    @Test func searchByNameMatchesCaseInsensitive() {
        let project = makeProject()
        let task1 = makeTask(name: "Fix login bug", status: .idea, project: project)
        let task2 = makeTask(name: "Add dashboard", status: .idea, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task1, task2],
            selectedProjectIDs: [],
            searchText: "LOGIN"
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Fix login bug")
    }

    @Test func searchByDescriptionMatchesCaseInsensitive() {
        let project = makeProject()
        let task1 = makeTask(name: "Task A", status: .idea, project: project)
        task1.taskDescription = "Refactor the authentication module"
        let task2 = makeTask(name: "Task B", status: .idea, project: project)
        task2.taskDescription = "Update readme"

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task1, task2],
            selectedProjectIDs: [],
            searchText: "auth"
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Task A")
    }

    @Test func searchWithNilDescriptionDoesNotMatch() {
        let project = makeProject()
        let task = makeTask(name: "Unrelated", status: .idea, project: project)
        task.taskDescription = nil

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task],
            selectedProjectIDs: [],
            searchText: "search term"
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.isEmpty)
    }

    @Test func emptySearchShowsAllTasks() {
        let project = makeProject()
        let task1 = makeTask(name: "Task A", status: .idea, project: project)
        let task2 = makeTask(name: "Task B", status: .idea, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task1, task2],
            selectedProjectIDs: [],
            searchText: ""
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 2)
    }

    @Test func whitespaceOnlySearchShowsAllTasks() {
        let project = makeProject()
        let task1 = makeTask(name: "Task A", status: .idea, project: project)
        let task2 = makeTask(name: "Task B", status: .idea, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task1, task2],
            selectedProjectIDs: [],
            searchText: "   "
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 2)
    }

    @Test func searchCombinesWithProjectAndTypeFilters() {
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let bugA = makeTask(name: "Login bug", status: .idea, type: .bug, project: projectA)
        let featureA = makeTask(name: "Login feature", status: .idea, type: .feature, project: projectA)
        let bugB = makeTask(name: "Login issue", status: .idea, type: .bug, project: projectB)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [bugA, featureA, bugB],
            selectedProjectIDs: [projectA.id],
            selectedTypes: [.bug],
            searchText: "login"
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Login bug")
    }

    @Test func searchMatchesEitherNameOrDescription() {
        let project = makeProject()
        let task1 = makeTask(name: "Widget update", status: .idea, project: project)
        task1.taskDescription = "Improve the sidebar layout"
        let task2 = makeTask(name: "Sidebar refactor", status: .idea, project: project)
        task2.taskDescription = "Clean up old code"

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task1, task2],
            selectedProjectIDs: [],
            searchText: "sidebar"
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 2)
    }
}
