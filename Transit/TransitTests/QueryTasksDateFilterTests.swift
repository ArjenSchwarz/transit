import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for date filtering in QueryTasksIntent (completionDate, lastStatusChangeDate).
@MainActor @Suite(.serialized)
struct QueryTasksDateFilterTests {

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
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
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

    // MARK: - completionDate: Relative Dates

    @Test func completionDateRelativeToday() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let todayTask = makeTask(
            in: svc.context, project: project, name: "Done Today", displayId: 1, status: .done
        )
        todayTask.completionDate = Date()
        let oldTask = makeTask(
            in: svc.context, project: project, name: "Done Last Week", displayId: 2, status: .done
        )
        oldTask.completionDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())

        let parsed = try parseJSONArray(QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project, modelContext: svc.context
        ))
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Today")
    }

    @Test func completionDateRelativeThisWeek() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let thisWeekTask = makeTask(
            in: svc.context, project: project, name: "This Week", displayId: 1, status: .done
        )
        thisWeekTask.completionDate = Date()
        let oldTask = makeTask(
            in: svc.context, project: project, name: "Last Month", displayId: 2, status: .done
        )
        oldTask.completionDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())

        let parsed = try parseJSONArray(QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"this-week\"}}",
            projectService: svc.project, modelContext: svc.context
        ))
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "This Week")
    }

    @Test func completionDateRelativeThisMonth() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let thisMonthTask = makeTask(
            in: svc.context, project: project, name: "This Month", displayId: 1, status: .done
        )
        thisMonthTask.completionDate = Date()
        let oldTask = makeTask(
            in: svc.context, project: project, name: "Two Months Ago", displayId: 2, status: .done
        )
        oldTask.completionDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())

        let parsed = try parseJSONArray(QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"this-month\"}}",
            projectService: svc.project, modelContext: svc.context
        ))
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "This Month")
    }

    // MARK: - lastStatusChangeDate

    @Test func lastStatusChangeDateRelativeToday() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Changed Today", displayId: 1)
        let oldTask = makeTask(
            in: svc.context, project: project, name: "Changed Last Week", displayId: 2
        )
        oldTask.lastStatusChangeDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let parsed = try parseJSONArray(QueryTasksIntent.execute(
            input: "{\"lastStatusChangeDate\":{\"relative\":\"today\"}}",
            projectService: svc.project, modelContext: svc.context
        ))
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Changed Today")
    }

    // MARK: - Absolute Date Range

    @Test func completionDateAbsoluteRange() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        fmt.timeZone = TimeZone.current

        let inRange = makeTask(
            in: svc.context, project: project, name: "In Range", displayId: 1, status: .done
        )
        inRange.completionDate = fmt.date(from: "2026-02-05")

        let outOfRange = makeTask(
            in: svc.context, project: project, name: "Out of Range", displayId: 2, status: .done
        )
        outOfRange.completionDate = fmt.date(from: "2026-01-15")

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"2026-02-01\",\"to\":\"2026-02-11\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "In Range")
    }

    @Test func absoluteRangeWithOnlyFromDate() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        fmt.timeZone = TimeZone.current

        let afterTask = makeTask(
            in: svc.context, project: project, name: "After", displayId: 1, status: .done
        )
        afterTask.completionDate = fmt.date(from: "2026-03-01")

        let beforeTask = makeTask(
            in: svc.context, project: project, name: "Before", displayId: 2, status: .done
        )
        beforeTask.completionDate = fmt.date(from: "2026-01-01")

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"2026-02-01\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "After")
    }

    // MARK: - Error Handling

    @Test func invalidRelativeDateReturnsError() throws {
        let svc = try makeServices()
        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"yesterday\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        #expect(try parseJSON(result)["error"] as? String == "INVALID_INPUT")
    }

    @Test func invalidAbsoluteDateFormatReturnsError() throws {
        let svc = try makeServices()
        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"not-a-date\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        #expect(try parseJSON(result)["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - Nil Date Exclusion

    @Test func tasksWithNilCompletionDateExcluded() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "No Completion", displayId: 1, status: .idea)
        let doneTask = makeTask(
            in: svc.context, project: project, name: "Done Task", displayId: 2, status: .done
        )
        doneTask.completionDate = Date()

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Task")
    }

    // MARK: - Combined Filters

    @Test func dateFilterCombinedWithStatusFilter() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let doneToday = makeTask(
            in: svc.context, project: project, name: "Done Today", displayId: 1, status: .done
        )
        doneToday.completionDate = Date()
        let abandonedToday = makeTask(
            in: svc.context, project: project, name: "Abandoned Today",
            displayId: 2, status: .abandoned
        )
        abandonedToday.completionDate = Date()

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"done\",\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Today")
    }

    @Test func dateFilterCombinedWithTypeFilter() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let bugDone = makeTask(
            in: svc.context, project: project, name: "Bug Done", type: .bug,
            displayId: 1, status: .done
        )
        bugDone.completionDate = Date()
        let featureDone = makeTask(
            in: svc.context, project: project, name: "Feature Done", type: .feature,
            displayId: 2, status: .done
        )
        featureDone.completionDate = Date()

        let result = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\",\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Bug Done")
    }

    // MARK: - Backward Compatibility

    @Test func existingQueriesWithoutDatesStillWork() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", type: .bug, displayId: 1)
        makeTask(in: svc.context, project: project, name: "Task B", type: .feature, displayId: 2)

        #expect(try parseJSONArray(QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}", projectService: svc.project, modelContext: svc.context
        )).count == 2)
        #expect(try parseJSONArray(QueryTasksIntent.execute(
            input: "{\"type\":\"bug\"}", projectService: svc.project, modelContext: svc.context
        )).count == 1)
        #expect(try parseJSONArray(QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
        )).count == 2)
    }
}
