import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct QueryTasksIntentDateFilterTests {

    private struct Services {
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        return Services(project: ProjectService(modelContext: context), context: context)
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
            modelContext: svc.context
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
            modelContext: svc.context
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
        let result = QueryTasksIntent.execute(input: input, projectService: svc.project, modelContext: svc.context)

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Today Done")
    }

    @Test func invalidDateFilterReturnsInvalidInputError() throws {
        let svc = try makeServices()

        let result = QueryTasksIntent.execute(
            input: "{\"completionDate\":{\"from\":\"2026-99-99\"}}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func existingQueriesRemainCompatibleWithoutDateFilters() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Idea A", displayId: 1, status: .idea)
        makeTask(in: svc.context, project: project, name: "Planning B", displayId: 2, status: .planning)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Idea A")
    }
}
