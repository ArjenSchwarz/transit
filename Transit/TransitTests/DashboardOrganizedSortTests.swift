import Foundation
import Testing
@testable import Transit

@MainActor
struct DashboardOrganizedSortTests {

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

    // MARK: - Project grouping

    @Test func groupsByProjectNameAlphabetically() {
        let now = Date(timeIntervalSince1970: 200_000)
        let projectB = makeProject(name: "Bravo")
        let projectA = makeProject(name: "Alpha")
        let taskB = makeTask(name: "Task B", status: .idea, project: projectB, lastStatusChange: now)
        let taskA = makeTask(name: "Task A", status: .idea, project: projectA, lastStatusChange: now)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [taskB, taskA],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let tasks = columns[.idea] ?? []
        #expect(tasks.count == 2)
        #expect(tasks[0].name == "Task A") // Alpha before Bravo
        #expect(tasks[1].name == "Task B")
    }

    // MARK: - Type ordering

    @Test func ordersTypesByEnumDeclaration() {
        let now = Date(timeIntervalSince1970: 200_000)
        let project = makeProject()
        let chore = makeTask(name: "Chore", status: .idea, type: .chore, project: project, lastStatusChange: now)
        let bug = makeTask(name: "Bug", status: .idea, type: .bug, project: project, lastStatusChange: now)
        let feature = makeTask(
            name: "Feature", status: .idea, type: .feature, project: project, lastStatusChange: now
        )

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [chore, bug, feature],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let tasks = columns[.idea] ?? []
        #expect(tasks.count == 3)
        #expect(tasks[0].name == "Bug")     // bug first in enum
        #expect(tasks[1].name == "Feature") // feature second
        #expect(tasks[2].name == "Chore")   // chore third
    }

    // MARK: - Display ID ordering

    @Test func ordersByDisplayIdAscending() {
        let now = Date(timeIntervalSince1970: 200_000)
        let project = makeProject()
        let task10 = makeTask(name: "T-10", status: .idea, project: project, lastStatusChange: now)
        task10.permanentDisplayId = 10
        let task5 = makeTask(name: "T-5", status: .idea, project: project, lastStatusChange: now)
        task5.permanentDisplayId = 5

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [task10, task5],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let tasks = columns[.idea] ?? []
        #expect(tasks.count == 2)
        #expect(tasks[0].name == "T-5")
        #expect(tasks[1].name == "T-10")
    }

    @Test func putsNilDisplayIdAfterPermanent() {
        let now = Date(timeIntervalSince1970: 200_000)
        let project = makeProject()
        let provisional = makeTask(name: "Provisional", status: .idea, project: project, lastStatusChange: now)
        let permanent = makeTask(name: "Permanent", status: .idea, project: project, lastStatusChange: now)
        permanent.permanentDisplayId = 1

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [provisional, permanent],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let tasks = columns[.idea] ?? []
        #expect(tasks.count == 2)
        #expect(tasks[0].name == "Permanent")
        #expect(tasks[1].name == "Provisional")
    }

    // MARK: - Tier preservation

    @Test func preservesHandoffFirstRule() {
        let now = Date(timeIntervalSince1970: 200_000)
        let project = makeProject()
        let specTask = makeTask(name: "Spec", status: .spec, project: project, lastStatusChange: now)
        let handoffTask = makeTask(
            name: "ReadyForImpl", status: .readyForImplementation, project: project,
            lastStatusChange: now.addingTimeInterval(-100)
        )

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [specTask, handoffTask],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let specColumn = columns[.spec] ?? []
        #expect(specColumn.count == 2)
        #expect(specColumn[0].name == "ReadyForImpl")
    }

    @Test func preservesDoneBeforeAbandoned() {
        let now = Date(timeIntervalSince1970: 200_000)
        let project = makeProject()
        let abandoned = makeTask(
            name: "Abandoned", status: .abandoned, project: project,
            lastStatusChange: now, completionDate: now
        )
        let done = makeTask(
            name: "Done", status: .done, project: project,
            lastStatusChange: now.addingTimeInterval(-100),
            completionDate: now.addingTimeInterval(-100)
        )

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [abandoned, done],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let terminal = columns[.doneAbandoned] ?? []
        #expect(terminal.count == 2)
        #expect(terminal[0].name == "Done")
        #expect(terminal[1].name == "Abandoned")
    }

    // MARK: - Tiebreaker

    @Test func usesDateAsTiebreaker() {
        let now = Date(timeIntervalSince1970: 200_000)
        let project = makeProject()
        let older = makeTask(
            name: "Older", status: .idea, project: project,
            lastStatusChange: now.addingTimeInterval(-100)
        )
        older.permanentDisplayId = 1
        let newer = makeTask(name: "Newer", status: .idea, project: project, lastStatusChange: now)
        newer.permanentDisplayId = 1

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [older, newer],
            selectedProjectIDs: [],
            sortOrder: .organized,
            now: now
        )

        let tasks = columns[.idea] ?? []
        #expect(tasks.count == 2)
        #expect(tasks[0].name == "Newer")
        #expect(tasks[1].name == "Older")
    }
}
