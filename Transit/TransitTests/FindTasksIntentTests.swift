import Foundation
import SwiftData
import Testing
@testable import Transit

private struct FindTaskSeed {
    let name: String
    let displayID: Int
    let type: TaskType
    let status: TaskStatus
    var completionDate: Date?
    let lastStatusChangeDate: Date
}

private func makeFindFilters(
    type: TaskType? = nil,
    project: ProjectEntity? = nil,
    status: TaskStatus? = nil,
    completionDateFilter: DateFilterOption? = nil,
    completionFromDate: Date? = nil,
    completionToDate: Date? = nil,
    lastStatusChangeDateFilter: DateFilterOption? = nil,
    lastStatusChangeFromDate: Date? = nil,
    lastStatusChangeToDate: Date? = nil
) -> FindTasksIntent.Filters {
    FindTasksIntent.Filters(
        type: type,
        project: project,
        status: status,
        completionDateFilter: completionDateFilter,
        completionFromDate: completionFromDate,
        completionToDate: completionToDate,
        lastStatusChangeDateFilter: lastStatusChangeDateFilter,
        lastStatusChangeFromDate: lastStatusChangeFromDate,
        lastStatusChangeToDate: lastStatusChangeToDate
    )
}

@MainActor @Suite(.serialized)
// swiftlint:disable:next type_body_length
struct FindTasksIntentTests {
    private struct TestEnv {
        let context: ModelContext
        let taskService: TaskService
    }

    private func makeEnv() throws -> TestEnv {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return TestEnv(
            context: context,
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator)
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String) -> Project {
        let project = Project(name: name, description: "desc", gitRepo: nil, colorHex: "#123456")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(in context: ModelContext, project: Project, seed: FindTaskSeed) -> TransitTask {
        let task = TransitTask(
            name: seed.name,
            type: seed.type,
            project: project,
            displayID: .permanent(seed.displayID)
        )
        StatusEngine.initializeNewTask(task)
        if seed.status != .idea { StatusEngine.applyTransition(task: task, to: seed.status) }
        if let completionDate = seed.completionDate { task.completionDate = completionDate }
        task.lastStatusChangeDate = seed.lastStatusChangeDate
        context.insert(task)
        return task
    }

    @Test func executeReturnsAllTasksWhenNoFiltersAreProvided() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context, name: "Main")
        let now = Date.now
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "Oldest",
                displayID: 1,
                type: .feature,
                status: .idea,
                lastStatusChangeDate: now.addingTimeInterval(-200)
            )
        )
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "Newest",
                displayID: 2,
                type: .bug,
                status: .inProgress,
                lastStatusChangeDate: now
            )
        )
        let result = try FindTasksIntent.execute(filters: makeFindFilters(), taskService: env.taskService)
        #expect(result.count == 2)
        #expect(result[0].name == "Newest")
        #expect(result[1].name == "Oldest")
    }

    @Test func executeAppliesAndLogicAcrossAllFilters() throws {
        let env = try makeEnv()
        let (alpha, beta) = (makeProject(in: env.context, name: "Alpha"), makeProject(in: env.context, name: "Beta"))
        let now = Date.now
        _ = makeTask(
            in: env.context,
            project: alpha,
            seed: FindTaskSeed(
                name: "Expected",
                displayID: 1,
                type: .feature,
                status: .done,
                completionDate: now,
                lastStatusChangeDate: now
            )
        )
        _ = makeTask(
            in: env.context,
            project: alpha,
            seed: FindTaskSeed(
                name: "Wrong Type",
                displayID: 2,
                type: .bug,
                status: .done,
                completionDate: now,
                lastStatusChangeDate: now
            )
        )
        _ = makeTask(
            in: env.context,
            project: beta,
            seed: FindTaskSeed(
                name: "Wrong Project",
                displayID: 3,
                type: .feature,
                status: .done,
                completionDate: now,
                lastStatusChangeDate: now
            )
        )
        let result = try FindTasksIntent.execute(
            filters: makeFindFilters(
                type: .feature,
                project: ProjectEntity.from(alpha),
                status: .done,
                completionDateFilter: .today,
                lastStatusChangeDateFilter: .today
            ),
            taskService: env.taskService
        )
        #expect(result.map(\.name) == ["Expected"])
    }

    @Test func executeSupportsCompletionDateCustomRange() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context, name: "Date")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayMinus2 = calendar.date(byAdding: .day, value: -2, to: today)!
        let dayMinus3 = calendar.date(byAdding: .day, value: -3, to: today)!
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "In Range",
                displayID: 1,
                type: .feature,
                status: .done,
                completionDate: dayMinus2,
                lastStatusChangeDate: today
            )
        )
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "Out Of Range",
                displayID: 2,
                type: .feature,
                status: .done,
                completionDate: dayMinus3,
                lastStatusChangeDate: today
            )
        )
        let result = try FindTasksIntent.execute(
            filters: makeFindFilters(
                completionDateFilter: .customRange,
                completionFromDate: dayMinus2,
                completionToDate: dayMinus1
            ),
            taskService: env.taskService
        )
        #expect(result.count == 1)
        #expect(result[0].name == "In Range")
    }

    @Test func executeSupportsLastStatusChangeDateCustomRange() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context, name: "Changed")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayMinus2 = calendar.date(byAdding: .day, value: -2, to: today)!
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "In Range",
                displayID: 1,
                type: .feature,
                status: .inProgress,
                lastStatusChangeDate: dayMinus1
            )
        )
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "Out Of Range",
                displayID: 2,
                type: .feature,
                status: .inProgress,
                lastStatusChangeDate: dayMinus2
            )
        )
        let result = try FindTasksIntent.execute(
            filters: makeFindFilters(
                lastStatusChangeDateFilter: .customRange,
                lastStatusChangeFromDate: dayMinus1,
                lastStatusChangeToDate: today
            ),
            taskService: env.taskService
        )
        #expect(result.count == 1)
        #expect(result[0].name == "In Range")
    }

    @Test func executeLimitsResultsToTwoHundred() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context, name: "Many")
        let base = Date.now
        for index in 0..<205 {
            _ = makeTask(
                in: env.context,
                project: project,
                seed: FindTaskSeed(
                    name: "Task \(index)",
                    displayID: index + 1,
                    type: .feature,
                    status: .idea,
                    lastStatusChangeDate: base.addingTimeInterval(TimeInterval(index))
                )
            )
        }
        let result = try FindTasksIntent.execute(filters: makeFindFilters(), taskService: env.taskService)
        #expect(result.count == 200)
        #expect(result.first?.name == "Task 204")
        #expect(result.last?.name == "Task 5")
    }

    @Test func executeReturnsEmptyArrayWhenNoMatches() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context, name: "Main")
        _ = makeTask(
            in: env.context,
            project: project,
            seed: FindTaskSeed(
                name: "Task",
                displayID: 1,
                type: .feature,
                status: .idea,
                lastStatusChangeDate: .now
            )
        )
        let result = try FindTasksIntent.execute(
            filters: makeFindFilters(status: .abandoned),
            taskService: env.taskService
        )
        #expect(result.isEmpty)
    }

    @Test func executeThrowsInvalidDateWhenCustomRangeIsInverted() throws {
        let env = try makeEnv()
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        #expect(throws: VisualIntentError.self) {
            _ = try FindTasksIntent.execute(
                filters: makeFindFilters(
                    completionDateFilter: .customRange,
                    completionFromDate: tomorrow,
                    completionToDate: today
                ),
                taskService: env.taskService
            )
        }
    }
}
