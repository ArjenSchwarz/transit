import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct FindTasksIntentTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        in context: ModelContext,
        project: Project,
        name: String = "Task",
        type: TaskType = .feature,
        displayId: Int,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(name: name, type: type, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        context.insert(task)
        return task
    }

    private func makeInput(
        type: TaskType? = nil,
        project: ProjectEntity? = nil,
        status: TaskStatus? = nil,
        completionDateFilter: DateFilterOption? = nil,
        lastChangedFilter: DateFilterOption? = nil,
        completionFromDate: Date? = nil,
        completionToDate: Date? = nil,
        lastChangedFromDate: Date? = nil,
        lastChangedToDate: Date? = nil
    ) -> FindTasksIntent.Input {
        FindTasksIntent.Input(
            type: type,
            project: project,
            status: status,
            completionDateFilter: completionDateFilter,
            lastChangedFilter: lastChangedFilter,
            completionFromDate: completionFromDate,
            completionToDate: completionToDate,
            lastChangedFromDate: lastChangedFromDate,
            lastChangedToDate: lastChangedToDate
        )
    }

    // MARK: - No Filters (returns all tasks)

    @Test func noFiltersReturnsAllTasks() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, name: "Task A", displayId: 1)
        makeTask(in: context, project: project, name: "Task B", displayId: 2)
        makeTask(in: context, project: project, name: "Task C", displayId: 3)

        let result = try FindTasksIntent.execute(input: makeInput(), modelContext: context)
        #expect(result.count == 3)
    }

    @Test func noTasksReturnsEmptyArray() throws {
        let context = try makeContext()

        let result = try FindTasksIntent.execute(input: makeInput(), modelContext: context)
        #expect(result.isEmpty)
    }

    // MARK: - Type Filter

    @Test func filterByType() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, name: "Bug Task", type: .bug, displayId: 1)
        makeTask(in: context, project: project, name: "Feature Task", type: .feature, displayId: 2)

        let result = try FindTasksIntent.execute(
            input: makeInput(type: .bug),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Bug Task")
    }

    // MARK: - Project Filter

    @Test func filterByProject() throws {
        let context = try makeContext()
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")
        makeTask(in: context, project: projectA, name: "Task in A", displayId: 1)
        makeTask(in: context, project: projectB, name: "Task in B", displayId: 2)

        let entityA = ProjectEntity.from(projectA)
        let result = try FindTasksIntent.execute(
            input: makeInput(project: entityA),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Task in A")
    }

    // MARK: - Status Filter

    @Test func filterByStatus() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, name: "Idea Task", displayId: 1, status: .idea)
        makeTask(in: context, project: project, name: "Done Task", displayId: 2, status: .done)

        let result = try FindTasksIntent.execute(
            input: makeInput(status: .done),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Done Task")
    }

    // MARK: - AND Logic (Multiple Filters)

    @Test func multipleFiltersApplyANDLogic() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let bugDone = makeTask(
            in: context, project: project, name: "Bug Done", type: .bug, displayId: 1, status: .done
        )
        bugDone.completionDate = Date()
        let featureDone = makeTask(
            in: context, project: project, name: "Feature Done", type: .feature,
            displayId: 2, status: .done
        )
        featureDone.completionDate = Date()
        makeTask(
            in: context, project: project, name: "Bug Idea", type: .bug, displayId: 3, status: .idea
        )

        let result = try FindTasksIntent.execute(
            input: makeInput(type: .bug, status: .done),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Bug Done")
    }

    @Test func allFiltersAppliedTogether() throws {
        let context = try makeContext()
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")

        let match = makeTask(
            in: context, project: projectA, name: "Match", type: .bug,
            displayId: 1, status: .done
        )
        match.completionDate = Date()

        let wrongProject = makeTask(
            in: context, project: projectB, name: "Wrong Project", type: .bug,
            displayId: 2, status: .done
        )
        wrongProject.completionDate = Date()

        let wrongType = makeTask(
            in: context, project: projectA, name: "Wrong Type", type: .feature,
            displayId: 3, status: .done
        )
        wrongType.completionDate = Date()

        let entityA = ProjectEntity.from(projectA)
        let result = try FindTasksIntent.execute(
            input: makeInput(
                type: .bug,
                project: entityA,
                status: .done,
                completionDateFilter: .today
            ),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Match")
    }

    // MARK: - Sort Order

    @Test func resultsSortedByLastStatusChangeDateDescending() throws {
        let context = try makeContext()
        let project = makeProject(in: context)

        let older = makeTask(in: context, project: project, name: "Older", displayId: 1)
        older.lastStatusChangeDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!

        let newer = makeTask(in: context, project: project, name: "Newer", displayId: 2)
        newer.lastStatusChangeDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!

        makeTask(in: context, project: project, name: "Newest", displayId: 3)

        let result = try FindTasksIntent.execute(input: makeInput(), modelContext: context)
        #expect(result.count == 3)
        #expect(result[0].name == "Newest")
        #expect(result[1].name == "Newer")
        #expect(result[2].name == "Older")
    }

    // MARK: - Result Limit

    @Test func resultsLimitedTo200() throws {
        let context = try makeContext()
        let project = makeProject(in: context)

        for index in 1...210 {
            makeTask(in: context, project: project, name: "Task \(index)", displayId: index)
        }

        let result = try FindTasksIntent.execute(input: makeInput(), modelContext: context)
        #expect(result.count == 200)
    }

    // MARK: - TaskEntity Properties

    @Test func resultEntitiesHaveCorrectProperties() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "My Project")
        let task = makeTask(
            in: context, project: project, name: "My Task", type: .bug,
            displayId: 42, status: .inProgress
        )

        let result = try FindTasksIntent.execute(input: makeInput(), modelContext: context)
        #expect(result.count == 1)

        let entity = try #require(result.first)
        #expect(entity.taskId == task.id)
        #expect(entity.displayId == 42)
        #expect(entity.name == "My Task")
        #expect(entity.status == "in-progress")
        #expect(entity.type == "bug")
        #expect(entity.projectId == project.id)
        #expect(entity.projectName == "My Project")
    }
}
