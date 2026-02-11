import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct QueryTasksIntentTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
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

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - No Filters

    @Test func noFiltersReturnsAllTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)
        makeTask(in: svc.context, project: project, name: "Task B", displayId: 2)
        makeTask(in: svc.context, project: project, name: "Task C", displayId: 3)

        let result = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 3)
    }

    @Test func emptyInputReturnsAllTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)

        let result = QueryTasksIntent.execute(
            input: "", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
    }

    // MARK: - Status Filter

    @Test func statusFilterReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Idea Task", displayId: 1, status: .idea)
        makeTask(in: svc.context, project: project, name: "Planning Task", displayId: 2, status: .planning)
        makeTask(in: svc.context, project: project, name: "Another Idea", displayId: 3, status: .idea)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
        for item in parsed {
            #expect(item["status"] as? String == "idea")
        }
    }

    // MARK: - Project Filter

    @Test func projectFilterReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "Project A")
        let projectB = makeProject(in: svc.context, name: "Project B")
        makeTask(in: svc.context, project: projectA, name: "A Task", displayId: 1)
        makeTask(in: svc.context, project: projectB, name: "B Task", displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(projectA.id.uuidString)\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "A Task")
    }

    @Test func projectNotFoundForInvalidProjectId() throws {
        let svc = try makeServices()

        let fakeId = UUID().uuidString
        let result = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(fakeId)\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "PROJECT_NOT_FOUND")
    }

    // MARK: - Type Filter

    @Test func typeFilterReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Bug Task", type: .bug, displayId: 1)
        makeTask(in: svc.context, project: project, name: "Feature Task", type: .feature, displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\"}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["type"] as? String == "bug")
    }

    // MARK: - Response Format

    @Test func responseContainsAllRequiredFields() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 5)

        let result = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        let item = try #require(parsed.first)

        #expect(item["taskId"] is String)
        #expect(item["displayId"] is Int)
        #expect(item["name"] is String)
        #expect(item["status"] is String)
        #expect(item["type"] is String)
        #expect(item["projectId"] is String)
        #expect(item["projectName"] is String)
        #expect(item.keys.contains("completionDate"))
        #expect(item.keys.contains("lastStatusChangeDate"))
    }

    // MARK: - Date Filtering - Completion Date

    @Test func completionDateFilterWithRelativeTodayReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        // Create tasks with different completion dates
        let taskToday = makeTask(
            in: svc.context, project: project, name: "Done Today", displayId: 1, status: .done
        )
        let taskYesterday = makeTask(
            in: svc.context, project: project, name: "Done Yesterday", displayId: 2, status: .done
        )

        // Manually set completion dates
        taskToday.completionDate = Date()
        taskYesterday.completionDate = Date().addingTimeInterval(-86400)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Today")
    }

    @Test func completionDateFilterWithRelativeThisWeekReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let taskThisWeek = makeTask(
            in: svc.context, project: project, name: "Done This Week", displayId: 1, status: .done
        )
        let taskLastWeek = makeTask(
            in: svc.context, project: project, name: "Done Last Week", displayId: 2, status: .done
        )

        taskThisWeek.completionDate = Date()
        taskLastWeek.completionDate = Date().addingTimeInterval(-7 * 86400)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"this-week\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done This Week")
    }

    @Test func completionDateFilterWithRelativeThisMonthReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let taskThisMonth = makeTask(
            in: svc.context, project: project, name: "Done This Month", displayId: 1, status: .done
        )
        let taskLastMonth = makeTask(
            in: svc.context, project: project, name: "Done Last Month", displayId: 2, status: .done
        )

        let calendar = Calendar.current
        taskThisMonth.completionDate = Date()
        taskLastMonth.completionDate = calendar.date(byAdding: .month, value: -1, to: Date())

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"this-month\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done This Month")
    }

    @Test func completionDateFilterWithAbsoluteRangeReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let calendar = Calendar.current
        let task1 = makeTask(in: svc.context, project: project, name: "Task 1", displayId: 1, status: .done)
        let task2 = makeTask(in: svc.context, project: project, name: "Task 2", displayId: 2, status: .done)
        let task3 = makeTask(in: svc.context, project: project, name: "Task 3", displayId: 3, status: .done)

        task1.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))
        task2.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))
        task3.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"2026-02-01\",\"to\":\"2026-02-11\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
        let names = parsed.compactMap { $0["name"] as? String }.sorted()
        #expect(names == ["Task 1", "Task 2"])
    }

    @Test func completionDateFilterWithOnlyFromReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let calendar = Calendar.current
        let task1 = makeTask(in: svc.context, project: project, name: "Task 1", displayId: 1, status: .done)
        let task2 = makeTask(in: svc.context, project: project, name: "Task 2", displayId: 2, status: .done)

        task1.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))
        task2.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"2026-02-10\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Task 2")
    }

    @Test func completionDateFilterWithOnlyToReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let calendar = Calendar.current
        let task1 = makeTask(in: svc.context, project: project, name: "Task 1", displayId: 1, status: .done)
        let task2 = makeTask(in: svc.context, project: project, name: "Task 2", displayId: 2, status: .done)

        task1.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))
        task2.completionDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"to\":\"2026-02-10\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Task 1")
    }

    @Test func completionDateFilterExcludesTasksWithNilCompletionDate() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let taskWithDate = makeTask(
            in: svc.context, project: project, name: "Done Task", displayId: 1, status: .done
        )
        let taskWithoutDate = makeTask(
            in: svc.context, project: project, name: "In Progress Task", displayId: 2, status: .inProgress
        )

        taskWithDate.completionDate = Date()
        // taskWithoutDate has nil completionDate

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Task")
    }

    // MARK: - Date Filtering - Last Status Change Date

    @Test func lastStatusChangeDateFilterWithRelativeTodayReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let taskToday = makeTask(in: svc.context, project: project, name: "Changed Today", displayId: 1)
        let taskYesterday = makeTask(in: svc.context, project: project, name: "Changed Yesterday", displayId: 2)

        taskToday.lastStatusChangeDate = Date()
        taskYesterday.lastStatusChangeDate = Date().addingTimeInterval(-86400)

        let result = QueryTasksIntent.execute(
            input: "{\"lastStatusChangeDate\":{\"relative\":\"today\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Changed Today")
    }

    @Test func lastStatusChangeDateFilterWithAbsoluteRangeReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let calendar = Calendar.current
        let task1 = makeTask(in: svc.context, project: project, name: "Task 1", displayId: 1)
        let task2 = makeTask(in: svc.context, project: project, name: "Task 2", displayId: 2)
        let task3 = makeTask(in: svc.context, project: project, name: "Task 3", displayId: 3)

        task1.lastStatusChangeDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        task2.lastStatusChangeDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!
        task3.lastStatusChangeDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!

        let result = QueryTasksIntent.execute(
            input: "{\"lastStatusChangeDate\":{\"from\":\"2026-02-01\",\"to\":\"2026-02-11\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
        let names = parsed.compactMap { $0["name"] as? String }.sorted()
        #expect(names == ["Task 1", "Task 2"])
    }

    // MARK: - Date Filtering - Combined Filters

    @Test func combinedDateAndStatusFiltersReturnMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let doneToday = makeTask(
            in: svc.context, project: project, name: "Done Today", displayId: 1, status: .done
        )
        let doneYesterday = makeTask(
            in: svc.context, project: project, name: "Done Yesterday", displayId: 2, status: .done
        )
        let ideaToday = makeTask(
            in: svc.context, project: project, name: "Idea Today", displayId: 3, status: .idea
        )

        doneToday.completionDate = Date()
        doneYesterday.completionDate = Date().addingTimeInterval(-86400)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"done\",\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Today")
    }

    @Test func bothDateFiltersAppliedTogether() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let calendar = Calendar.current
        let task1 = makeTask(in: svc.context, project: project, name: "Task 1", displayId: 1, status: .done)
        let task2 = makeTask(in: svc.context, project: project, name: "Task 2", displayId: 2, status: .done)

        let feb5 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!
        task1.completionDate = feb5
        task1.lastStatusChangeDate = feb5

        let feb15 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        task2.completionDate = feb15
        task2.lastStatusChangeDate = feb15

        let result = QueryTasksIntent.execute(
            input: """
            {
                "completionDate": {"from": "2026-02-01", "to": "2026-02-10"},
                "lastStatusChangeDate": {"from": "2026-02-01", "to": "2026-02-10"}
            }
            """,
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Task 1")
    }

    // MARK: - Date Filtering - Backward Compatibility

    @Test func existingQueriesWithoutDateFiltersStillWork() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)
        makeTask(in: svc.context, project: project, name: "Task B", displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
    }

    @Test func emptyDateFilterObjectIsIgnored() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
    }

    @Test func invalidDateFormatIsIgnored() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1, status: .done)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"invalid-date\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        // Invalid date format results in nil dates, which creates an absolute range with nil values
        // This should match all tasks (no filtering applied)
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
    }
}
