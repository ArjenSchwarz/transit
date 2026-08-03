import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
// swiftlint:disable:next type_body_length
struct QueryTasksIntentDateFilterTests {

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
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
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

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func completionDateRelativeTodayFiltersTasksWithCompletionToday() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let calendar = Calendar.current
        let now = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        makeTask(
            in: svc.context,
            project: project,
            name: "Done Today",
            displayId: 1,
            status: .done,
            completionDate: now
        )
        makeTask(
            in: svc.context,
            project: project,
            name: "Done Yesterday",
            displayId: 2,
            status: .done,
            completionDate: yesterday
        )
        makeTask(
            in: svc.context,
            project: project,
            name: "Not Completed",
            displayId: 3,
            status: .inProgress
        )

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"relative\":\"today\"}}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Done Today")
    }

    @Test func lastStatusChangeDateAbsoluteRangeFiltersInclusively() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayMinus2 = calendar.date(byAdding: .day, value: -2, to: today)!
        let dayMinus3 = calendar.date(byAdding: .day, value: -3, to: today)!

        makeTask(in: svc.context, project: project, name: "Out Of Range", displayId: 1, lastStatusChangeDate: dayMinus3)
        makeTask(in: svc.context, project: project, name: "Range Start", displayId: 2, lastStatusChangeDate: dayMinus2)
        makeTask(in: svc.context, project: project, name: "Range End", displayId: 3, lastStatusChangeDate: dayMinus1)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        let fromDateString = dateFormatter.string(from: dayMinus2)
        let toDateString = dateFormatter.string(from: dayMinus1)
        let result = QueryTasksIntent.execute(
            input: "{\"lastStatusChangeDate\":{\"from\":\"\(fromDateString)\",\"to\":\"\(toDateString)\"}}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
        let names = Set(parsed.compactMap { $0["name"] as? String })
        #expect(names.contains("Range Start"))
        #expect(names.contains("Range End"))
    }

    @Test func relativeDateFilterTakesPrecedenceOverAbsoluteDates() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let calendar = Calendar.current
        let now = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let today = calendar.startOfDay(for: now)
        let oldFrom = calendar.date(byAdding: .day, value: -10, to: today)!
        let oldTo = calendar.date(byAdding: .day, value: -7, to: today)!

        makeTask(
            in: svc.context,
            project: project,
            name: "Today Done",
            displayId: 1,
            status: .done,
            completionDate: now
        )
        makeTask(
            in: svc.context,
            project: project,
            name: "Yesterday Done",
            displayId: 2,
            status: .done,
            completionDate: yesterday
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        let fromDateString = dateFormatter.string(from: oldFrom)
        let toDateString = dateFormatter.string(from: oldTo)
        let input = """
        {"completionDate":{"relative":"today","from":"\(fromDateString)","to":"\(toDateString)"}}
        """
        let result = QueryTasksIntent.execute(
            input: input,
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Today Done")
    }

    @Test func completionDateFromOnlyKeepsOpenUpperBound() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let fromDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let beforeFrom = calendar.date(byAdding: .day, value: -2, to: today)!

        makeTask(in: svc.context, project: project, name: "Before From", displayId: 1, completionDate: beforeFrom)
        makeTask(in: svc.context, project: project, name: "At From", displayId: 2, completionDate: fromDate)
        makeTask(in: svc.context, project: project, name: "After From", displayId: 3, completionDate: today)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        let fromDateString = dateFormatter.string(from: fromDate)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"\(fromDateString)\"}}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let names = Set(try parseJSONArray(result).compactMap { $0["name"] as? String })
        #expect(names == ["At From", "After From"])
    }

    @Test func completionDateToOnlyKeepsOpenLowerBound() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let toDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let beforeTo = calendar.date(byAdding: .day, value: -2, to: today)!

        makeTask(in: svc.context, project: project, name: "Before To", displayId: 1, completionDate: beforeTo)
        makeTask(in: svc.context, project: project, name: "At To", displayId: 2, completionDate: toDate)
        makeTask(in: svc.context, project: project, name: "After To", displayId: 3, completionDate: today)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        let toDateString = dateFormatter.string(from: toDate)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"to\":\"\(toDateString)\"}}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let names = Set(try parseJSONArray(result).compactMap { $0["name"] as? String })
        #expect(names == ["Before To", "At To"])
    }

    @Test func absoluteSameDayRangeIncludesTasksOnThatDay() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        makeTask(
            in: svc.context,
            project: project,
            name: "Today",
            displayId: 1,
            completionDate: today.addingTimeInterval(12 * 60 * 60)
        )
        makeTask(
            in: svc.context,
            project: project,
            name: "Yesterday",
            displayId: 2,
            completionDate: yesterday.addingTimeInterval(12 * 60 * 60)
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        let dateString = dateFormatter.string(from: today)

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"\(dateString)\",\"to\":\"\(dateString)\"}}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let names = Set(try parseJSONArray(result).compactMap { $0["name"] as? String })
        #expect(names == ["Today"])
    }

    @Test("QueryTasksIntent rejects reversed absolute date ranges for both date fields")
    func reversedAbsoluteDateRangesReturnInvalidInput() throws {
        let svc = try makeServices()

        for field in ["completionDate", "lastStatusChangeDate"] {
            let result = QueryTasksIntent.execute(
                input: "{\"\(field)\":{\"from\":\"2026-07-20\",\"to\":\"2026-07-01\"}}",
                projectService: svc.project,
                taskService: svc.task,
                milestoneService: svc.milestone
            )

            let parsed = try parseJSON(result)
            #expect(parsed["error"] as? String == "INVALID_INPUT")
            #expect(parsed["hint"] as? String == "Invalid \(field) filter format")
        }
    }

    @Test func invalidDateFilterReturnsInvalidInputError() throws {
        let svc = try makeServices()

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"2026-99-99\"}}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test("QueryTasksIntent rejects malformed absolute date strings", arguments: [
        "2026-02-30", // Normalized invalid day
        "2026-13-01", // Invalid month boundary
        "2026-2-01", // Non-padded month
        "2026-02-１" // Non-ASCII digit
    ])
    func malformedAbsoluteDateStringsReturnInvalidInput(value: String) throws {
        let svc = try makeServices()

        for field in ["completionDate", "lastStatusChangeDate"] {
            let result = QueryTasksIntent.execute(
                input: "{\"\(field)\":{\"from\":\"\(value)\"}}",
                projectService: svc.project,
                taskService: svc.task,
                milestoneService: svc.milestone
            )

            let parsed = try parseJSON(result)
            #expect(parsed["error"] as? String == "INVALID_INPUT")
        }
    }

    @Test func existingQueriesRemainCompatibleWithoutDateFilters() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Idea A", displayId: 1, status: .idea)
        makeTask(in: svc.context, project: project, name: "Planning B", displayId: 2, status: .planning)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Idea A")
    }

    @Test("Empty date filter objects are no-ops for both date fields")
    func emptyDateFilterObjectsReturnAllTasks() throws {
        let inputs = [
            "{\"completionDate\":{}}",
            "{\"lastStatusChangeDate\":{}}",
            "{\"completionDate\":{},\"lastStatusChangeDate\":{}}"
        ]

        for input in inputs {
            let svc = try makeServices()
            let project = makeProject(in: svc.context)
            makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)
            makeTask(in: svc.context, project: project, name: "Task B", displayId: 2, status: .done)
            makeTask(in: svc.context, project: project, name: "Task C", displayId: 3, status: .abandoned)

            let result = QueryTasksIntent.execute(
                input: input,
                projectService: svc.project,
                taskService: svc.task,
                milestoneService: svc.milestone
            )

            let names = Set(try parseJSONArray(result).compactMap { $0["name"] as? String })
            #expect(names == ["Task A", "Task B", "Task C"], "Input \(input) must not filter tasks")
        }
    }
}
