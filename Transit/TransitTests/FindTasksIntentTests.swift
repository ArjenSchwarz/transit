import Foundation
import Testing
import SwiftData
@testable import Transit

@MainActor
@Suite(.serialized)
struct FindTasksIntentTests {

    // MARK: - Test Fixtures

    private struct TestContext {
        let context: ModelContext
        let taskService: TaskService
        let projectService: ProjectService
    }

    private func makeTestContext() throws -> TestContext {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)

        return TestContext(
            context: context,
            taskService: taskService,
            projectService: projectService
        )
    }

    private func createProject(
        _ name: String,
        in context: ModelContext
    ) throws -> Project {
        let project = Project(name: name, description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        try context.save()
        return project
    }

    private func createTask(
        name: String,
        type: TaskType,
        status: TaskStatus,
        project: Project,
        taskService: TaskService,
        completionDate: Date? = nil,
        lastStatusChangeDate: Date? = nil
    ) async throws -> TransitTask {
        let task = try await taskService.createTask(
            name: name,
            description: nil,
            type: type,
            project: project,
            metadata: nil
        )

        // Update status if needed
        if status != .idea {
            try await taskService.updateStatus(task: task, to: status)
        }

        // Override dates if provided (for testing date filters)
        if let completionDate {
            task.completionDate = completionDate
        }
        if let lastStatusChangeDate {
            task.lastStatusChangeDate = lastStatusChangeDate
        }

        return task
    }

    // MARK: - No Filter Tests

    @Test("Returns all tasks when no filters specified")
    func returnsAllTasksWithNoFilters() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        _ = try await createTask(name: "Task 1", type: .feature, status: .idea, project: project, taskService: taskService)
        _ = try await createTask(name: "Task 2", type: .bug, status: .inProgress, project: project, taskService: taskService)
        _ = try await createTask(name: "Task 3", type: .chore, status: .done, project: project, taskService: taskService)

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 3)
    }

    @Test("Returns empty array when no tasks exist")
    func returnsEmptyArrayWhenNoTasks() async throws {
        let testContext = try makeTestContext()
        let projectService = testContext.projectService

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.isEmpty)
    }

    // MARK: - Type Filter Tests

    @Test("Filters by task type", arguments: TaskType.allCases)
    func filtersByTaskType(filterType: TaskType) async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        // Create tasks of different types
        _ = try await createTask(name: "Feature Task", type: .feature, status: .idea, project: project, taskService: taskService)
        _ = try await createTask(name: "Bug Task", type: .bug, status: .idea, project: project, taskService: taskService)
        _ = try await createTask(name: "Chore Task", type: .chore, status: .idea, project: project, taskService: taskService)

        let results = try await FindTasksIntent.execute(
            type: filterType,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 1)
        #expect(results.first?.type == filterType.rawValue)
    }

    // MARK: - Project Filter Tests

    @Test("Filters by project")
    func filtersByProject() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let projectA = try createProject("Project A", in: projectService.context)
        let projectB = try createProject("Project B", in: projectService.context)

        _ = try await createTask(name: "Task A1", type: .feature, status: .idea, project: projectA, taskService: taskService)
        _ = try await createTask(name: "Task A2", type: .bug, status: .idea, project: projectA, taskService: taskService)
        _ = try await createTask(name: "Task B1", type: .feature, status: .idea, project: projectB, taskService: taskService)

        let projectEntityA = ProjectEntity.from(projectA)

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: projectEntityA,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.projectId == projectA.id })
    }

    // MARK: - Status Filter Tests

    @Test("Filters by status", arguments: [TaskStatus.idea, .inProgress, .done])
    func filtersByStatus(filterStatus: TaskStatus) async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        _ = try await createTask(name: "Idea Task", type: .feature, status: .idea, project: project, taskService: taskService)
        _ = try await createTask(name: "In Progress Task", type: .feature, status: .inProgress, project: project, taskService: taskService)
        _ = try await createTask(name: "Done Task", type: .feature, status: .done, project: project, taskService: taskService)

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: filterStatus,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 1)
        #expect(results.first?.status == filterStatus.rawValue)
    }

    // MARK: - Completion Date Filter Tests

    @Test("Filters by completion date - today")
    func filtersByCompletionDateToday() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let task1 = try await createTask(name: "Completed Today", type: .feature, status: .done, project: project, taskService: taskService)
        task1.completionDate = today

        let task2 = try await createTask(name: "Completed Yesterday", type: .feature, status: .done, project: project, taskService: taskService)
        task2.completionDate = yesterday

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: .today,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 1)
        #expect(results.first?.name == "Completed Today")
    }

    @Test("Filters by completion date - custom range")
    func filtersByCompletionDateCustomRange() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        let calendar = Calendar.current
        let today = Date()
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: today)!
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!

        let task1 = try await createTask(name: "Task 3 days ago", type: .feature, status: .done, project: project, taskService: taskService)
        task1.completionDate = threeDaysAgo

        let task2 = try await createTask(name: "Task 5 days ago", type: .feature, status: .done, project: project, taskService: taskService)
        task2.completionDate = fiveDaysAgo

        let task3 = try await createTask(name: "Task 7 days ago", type: .feature, status: .done, project: project, taskService: taskService)
        task3.completionDate = sevenDaysAgo

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: .customRange,
            completionFromDate: calendar.date(byAdding: .day, value: -6, to: today),
            completionToDate: calendar.date(byAdding: .day, value: -2, to: today),
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Task 3 days ago" })
        #expect(results.contains { $0.name == "Task 5 days ago" })
    }

    @Test("Excludes tasks with nil completion date when filtering by completion date")
    func excludesNilCompletionDateWhenFiltering() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        _ = try await createTask(name: "Not Completed", type: .feature, status: .idea, project: project, taskService: taskService)

        let completedTask = try await createTask(name: "Completed", type: .feature, status: .done, project: project, taskService: taskService)
        completedTask.completionDate = Date()

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: .today,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 1)
        #expect(results.first?.name == "Completed")
    }

    // MARK: - Last Status Change Date Filter Tests

    @Test("Filters by last status change date - today")
    func filtersByLastStatusChangeDateToday() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let task1 = try await createTask(name: "Changed Today", type: .feature, status: .idea, project: project, taskService: taskService)
        task1.lastStatusChangeDate = today

        let task2 = try await createTask(name: "Changed Yesterday", type: .feature, status: .idea, project: project, taskService: taskService)
        task2.lastStatusChangeDate = yesterday

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: .today,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 1)
        #expect(results.first?.name == "Changed Today")
    }

    // MARK: - Multiple Filter Tests (AND Logic)

    @Test("Applies multiple filters with AND logic")
    func appliesMultipleFiltersWithAndLogic() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let projectA = try createProject("Project A", in: projectService.context)
        let projectB = try createProject("Project B", in: projectService.context)

        // Create various tasks
        _ = try await createTask(name: "Feature in A", type: .feature, status: .idea, project: projectA, taskService: taskService)
        _ = try await createTask(name: "Bug in A", type: .bug, status: .idea, project: projectA, taskService: taskService)
        _ = try await createTask(name: "Feature in B", type: .feature, status: .idea, project: projectB, taskService: taskService)
        _ = try await createTask(name: "Feature in A - In Progress", type: .feature, status: .inProgress, project: projectA, taskService: taskService)

        let projectEntityA = ProjectEntity.from(projectA)

        // Filter: type=feature AND project=A AND status=idea
        let results = try await FindTasksIntent.execute(
            type: .feature,
            project: projectEntityA,
            status: .idea,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 1)
        #expect(results.first?.name == "Feature in A")
    }

    @Test("Returns empty array when filters match no tasks")
    func returnsEmptyArrayWhenNoMatches() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        _ = try await createTask(name: "Feature Task", type: .feature, status: .idea, project: project, taskService: taskService)

        // Filter for bugs (none exist)
        let results = try await FindTasksIntent.execute(
            type: .bug,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.isEmpty)
    }

    // MARK: - Sort Order Tests

    @Test("Sorts results by lastStatusChangeDate descending")
    func sortsResultsByLastStatusChangeDateDescending() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        let calendar = Calendar.current
        let now = Date()

        let task1 = try await createTask(name: "Oldest", type: .feature, status: .idea, project: project, taskService: taskService)
        task1.lastStatusChangeDate = calendar.date(byAdding: .day, value: -3, to: now)!

        let task2 = try await createTask(name: "Newest", type: .feature, status: .idea, project: project, taskService: taskService)
        task2.lastStatusChangeDate = now

        let task3 = try await createTask(name: "Middle", type: .feature, status: .idea, project: project, taskService: taskService)
        task3.lastStatusChangeDate = calendar.date(byAdding: .day, value: -1, to: now)!

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 3)
        #expect(results[0].name == "Newest")
        #expect(results[1].name == "Middle")
        #expect(results[2].name == "Oldest")
    }

    // MARK: - Result Limit Tests

    @Test("Limits results to 200 tasks")
    func limitsResultsTo200Tasks() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        // Create 250 tasks
        for i in 1...250 {
            _ = try await createTask(name: "Task \(i)", type: .feature, status: .idea, project: project, taskService: taskService)
        }

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 200)
    }

    @Test("Returns most recent 200 tasks when limit exceeded")
    func returnsMostRecent200TasksWhenLimitExceeded() async throws {
        let testContext = try makeTestContext()
        let taskService = testContext.taskService
        let projectService = testContext.projectService
        let project = try createProject("Project A", in: projectService.context)

        let calendar = Calendar.current
        let now = Date()

        // Create 250 tasks with different lastStatusChangeDate values
        for i in 1...250 {
            let task = try await createTask(name: "Task \(i)", type: .feature, status: .idea, project: project, taskService: taskService)
            // Older tasks have earlier dates
            task.lastStatusChangeDate = calendar.date(byAdding: .day, value: -(250 - i), to: now)!
        }

        let results = try await FindTasksIntent.execute(
            type: nil,
            project: nil,
            status: nil,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFilter: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil,
            projectService: projectService
        )

        #expect(results.count == 200)
        // The most recent task should be "Task 250"
        #expect(results.first?.name == "Task 250")
        // The 200th task should be "Task 51" (250 - 199)
        #expect(results.last?.name == "Task 51")
    }
}
