import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct QueryTasksIntentEmptyDateFilterTests {

    private struct Services {
        let task: TaskService
        let project: ProjectService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        in context: ModelContext,
        project: Project,
        name: String,
        displayId: Int,
        status: TaskStatus = .idea,
        completionDate: Date? = nil,
        lastStatusChangeDate: Date? = nil
    ) -> TransitTask {
        let task = TransitTask(name: name, type: .feature, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        if let completionDate {
            task.completionDate = completionDate
        }
        if let lastStatusChangeDate {
            task.lastStatusChangeDate = lastStatusChangeDate
        }
        context.insert(task)
        return task
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("Empty date filters do not override other filters")
    func emptyDateFiltersRemainNoOpsWhenCombinedWithOtherFilters() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Idea", displayId: 1)
        makeTask(in: svc.context, project: project, name: "Done", displayId: 2, status: .done)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{},\"lastStatusChangeDate\":{},\"status\":\"done\"}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let names = Set(try parseJSONArray(result).compactMap { $0["name"] as? String })
        #expect(names == ["Done"])
    }

    @Test("Unknown nested keys remain ignored when a valid date bound is present")
    func unknownNestedKeysDoNotChangeValidDateFilters() throws {
        for field in ["completionDate", "lastStatusChangeDate"] {
            let svc = try makeServices()
            let project = makeProject(in: svc.context)
            makeTask(
                in: svc.context,
                project: project,
                name: "Included",
                displayId: 1,
                status: .done,
                completionDate: Date.now,
                lastStatusChangeDate: Date.now
            )

            let result = QueryTasksIntent.execute(
                input: "{\"\(field)\":{\"from\":\"2020-01-01\",\"unexpected\":null}}",
                projectService: svc.project,
                taskService: svc.task,
                milestoneService: svc.milestone
            )

            let names = Set(try parseJSONArray(result).compactMap { $0["name"] as? String })
            #expect(names == ["Included"], "Unknown nested key must not alter \(field) filtering")
        }
    }
}
