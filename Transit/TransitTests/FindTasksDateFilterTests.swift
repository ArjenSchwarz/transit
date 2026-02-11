import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for date filtering in FindTasksIntent (completionDate, lastStatusChangeDate).
@MainActor @Suite(.serialized)
struct FindTasksDateFilterTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String? = nil) -> Project {
        let projectName = name ?? "FTDF-\(UUID().uuidString.prefix(8))"
        let project = Project(name: projectName, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
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
        project: ProjectEntity? = nil,
        completionDateFilter: DateFilterOption? = nil,
        lastChangedFilter: DateFilterOption? = nil,
        completionFromDate: Date? = nil,
        completionToDate: Date? = nil,
        lastChangedFromDate: Date? = nil,
        lastChangedToDate: Date? = nil
    ) -> FindTasksIntent.Input {
        FindTasksIntent.Input(
            type: nil,
            project: project,
            status: nil,
            completionDateFilter: completionDateFilter,
            lastChangedFilter: lastChangedFilter,
            completionFromDate: completionFromDate,
            completionToDate: completionToDate,
            lastChangedFromDate: lastChangedFromDate,
            lastChangedToDate: lastChangedToDate
        )
    }

    // MARK: - Completion Date: Relative

    @Test func completionDateFilterToday() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let doneToday = makeTask(
            in: context, project: project, name: "Done Today", displayId: 1, status: .done
        )
        doneToday.completionDate = Date()
        let doneLastWeek = makeTask(
            in: context, project: project, name: "Done Last Week", displayId: 2, status: .done
        )
        doneLastWeek.completionDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())

        let entityP = ProjectEntity.from(project)
        let result = try FindTasksIntent.execute(
            input: makeInput(project: entityP, completionDateFilter: .today),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Done Today")
    }

    @Test func completionDateFilterThisWeek() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let thisWeek = makeTask(
            in: context, project: project, name: "This Week", displayId: 1, status: .done
        )
        thisWeek.completionDate = Date()
        let longAgo = makeTask(
            in: context, project: project, name: "Long Ago", displayId: 2, status: .done
        )
        longAgo.completionDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())

        let entityP = ProjectEntity.from(project)
        let result = try FindTasksIntent.execute(
            input: makeInput(project: entityP, completionDateFilter: .thisWeek),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "This Week")
    }

    @Test func completionDateFilterThisMonth() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let thisMonth = makeTask(
            in: context, project: project, name: "This Month", displayId: 1, status: .done
        )
        thisMonth.completionDate = Date()
        let twoMonthsAgo = makeTask(
            in: context, project: project, name: "Two Months Ago", displayId: 2, status: .done
        )
        twoMonthsAgo.completionDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())

        let entityP = ProjectEntity.from(project)
        let result = try FindTasksIntent.execute(
            input: makeInput(project: entityP, completionDateFilter: .thisMonth),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "This Month")
    }

    // MARK: - Completion Date: Custom Range

    @Test func completionDateFilterCustomRange() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        fmt.timeZone = TimeZone.current

        let inRange = makeTask(
            in: context, project: project, name: "In Range", displayId: 1, status: .done
        )
        inRange.completionDate = fmt.date(from: "2026-02-05")

        let outOfRange = makeTask(
            in: context, project: project, name: "Out of Range", displayId: 2, status: .done
        )
        outOfRange.completionDate = fmt.date(from: "2026-01-15")

        let entityP = ProjectEntity.from(project)
        let result = try FindTasksIntent.execute(
            input: makeInput(
                project: entityP,
                completionDateFilter: .customRange,
                completionFromDate: fmt.date(from: "2026-02-01"),
                completionToDate: fmt.date(from: "2026-02-11")
            ),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "In Range")
    }

    // MARK: - Nil Date Exclusion

    @Test func tasksWithNilCompletionDateExcludedFromFilter() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, name: "No Completion", displayId: 1, status: .idea)
        let done = makeTask(
            in: context, project: project, name: "Done Task", displayId: 2, status: .done
        )
        done.completionDate = Date()

        let entityP = ProjectEntity.from(project)
        let result = try FindTasksIntent.execute(
            input: makeInput(project: entityP, completionDateFilter: .today),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Done Task")
    }

    // MARK: - Last Status Change Date

    @Test func lastChangedFilterToday() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, name: "Changed Today", displayId: 1)
        let oldTask = makeTask(in: context, project: project, name: "Changed Last Week", displayId: 2)
        oldTask.lastStatusChangeDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let entityP = ProjectEntity.from(project)
        let result = try FindTasksIntent.execute(
            input: makeInput(project: entityP, lastChangedFilter: .today),
            modelContext: context
        )
        #expect(result.count == 1)
        #expect(result.first?.name == "Changed Today")
    }
}
