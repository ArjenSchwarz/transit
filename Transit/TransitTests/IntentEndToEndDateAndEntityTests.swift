import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for custom-range date filtering via FindTasksIntent and TaskEntity
/// property verification. [Task 14.4, 14.5]
@MainActor @Suite(.serialized)
struct IntentEndToEndDateAndEntityTests {

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
    private func makeProject(
        in context: ModelContext,
        name: String = "Test Project"
    ) -> Project {
        let project = Project(
            name: name, description: "A test project",
            gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    private func makeDateFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = Calendar.current
        fmt.timeZone = TimeZone.current
        return fmt
    }

    // MARK: - 14.4: Conditional Parameter Display (custom-range dates)

    @Test func findTasksWithCustomRangeCompletionDate() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "DateRangeProjectE2E")
        let entity = ProjectEntity.from(project)
        let task = TransitTask(
            name: "Done Task", type: .feature,
            project: project, displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(task)
        StatusEngine.applyTransition(task: task, to: .done)
        svc.context.insert(task)

        let fmt = makeDateFormatter()
        task.completionDate = fmt.date(from: "2026-02-05")

        let results = try FindTasksIntent.execute(
            input: FindTasksIntent.Input(
                type: nil, project: entity, status: nil,
                completionDateFilter: .customRange,
                lastChangedFilter: nil,
                completionFromDate: fmt.date(from: "2026-02-01"),
                completionToDate: fmt.date(from: "2026-02-10"),
                lastChangedFromDate: nil,
                lastChangedToDate: nil
            ),
            modelContext: svc.context
        )

        #expect(results.contains { $0.name == "Done Task" })
    }

    @Test func findTasksWithCustomRangeLastChanged() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "LastChangedRangeE2E")
        let entity = ProjectEntity.from(project)
        let task = TransitTask(
            name: "Changed Task", type: .bug,
            project: project, displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let fmt = makeDateFormatter()
        task.lastStatusChangeDate = fmt.date(from: "2026-02-05")!

        let results = try FindTasksIntent.execute(
            input: FindTasksIntent.Input(
                type: nil, project: entity, status: nil,
                completionDateFilter: nil,
                lastChangedFilter: .customRange,
                completionFromDate: nil,
                completionToDate: nil,
                lastChangedFromDate: fmt.date(from: "2026-02-01"),
                lastChangedToDate: fmt.date(from: "2026-02-10")
            ),
            modelContext: svc.context
        )

        #expect(results.contains { $0.name == "Changed Task" })
    }

    @Test func findTasksWithBothCustomRanges() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "BothRangesE2E")
        let entity = ProjectEntity.from(project)

        let fmt = makeDateFormatter()

        let match = TransitTask(
            name: "Match", type: .feature,
            project: project, displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(match)
        StatusEngine.applyTransition(task: match, to: .done)
        match.completionDate = fmt.date(from: "2026-02-05")
        match.lastStatusChangeDate = fmt.date(from: "2026-02-05")!
        svc.context.insert(match)

        let noMatch = TransitTask(
            name: "No Match", type: .feature,
            project: project, displayID: .permanent(2)
        )
        StatusEngine.initializeNewTask(noMatch)
        StatusEngine.applyTransition(task: noMatch, to: .done)
        noMatch.completionDate = fmt.date(from: "2026-01-15")
        noMatch.lastStatusChangeDate = fmt.date(from: "2026-02-05")!
        svc.context.insert(noMatch)

        let results = try FindTasksIntent.execute(
            input: FindTasksIntent.Input(
                type: nil, project: entity, status: nil,
                completionDateFilter: .customRange,
                lastChangedFilter: .customRange,
                completionFromDate: fmt.date(from: "2026-02-01"),
                completionToDate: fmt.date(from: "2026-02-10"),
                lastChangedFromDate: fmt.date(from: "2026-02-01"),
                lastChangedToDate: fmt.date(from: "2026-02-10")
            ),
            modelContext: svc.context
        )

        #expect(results.count { $0.projectName == "BothRangesE2E" } == 1)
        #expect(results.contains { $0.name == "Match" })
    }

    // MARK: - 14.5: TaskEntity Properties Accessible

    @Test func taskEntityContainsAllRequiredProperties() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "PropsProjectE2E")
        let entity = ProjectEntity.from(project)

        let createResult = try await AddTaskIntent.execute(
            input: AddTaskIntent.Input(
                name: "Property Check", taskDescription: "desc",
                type: .research, project: entity
            ),
            taskService: svc.task, projectService: svc.project
        )

        let findResults = try FindTasksIntent.execute(
            input: FindTasksIntent.Input(
                type: .research, project: entity, status: nil,
                completionDateFilter: nil, lastChangedFilter: nil,
                completionFromDate: nil, completionToDate: nil,
                lastChangedFromDate: nil, lastChangedToDate: nil
            ),
            modelContext: svc.context
        )

        let taskEntity = try #require(
            findResults.first { $0.taskId == createResult.taskId }
        )

        // Verify all required properties per req 3.9
        #expect(taskEntity.taskId == createResult.taskId)
        #expect(taskEntity.id == createResult.taskId.uuidString)
        #expect(taskEntity.displayId == createResult.displayId)
        #expect(taskEntity.name == "Property Check")
        #expect(taskEntity.status == "idea")
        #expect(taskEntity.type == "research")
        #expect(taskEntity.projectId == project.id)
        #expect(taskEntity.projectName == "PropsProjectE2E")
        #expect(taskEntity.lastStatusChangeDate != Date.distantPast)
        #expect(taskEntity.completionDate == nil)
    }

    @Test func taskEntityDisplayRepresentationHasExpectedValues() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 42,
            name: "My Task",
            status: "in-progress",
            type: "bug",
            projectId: UUID(),
            projectName: "Alpha",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        let title = String(localized: entity.displayRepresentation.title)
        #expect(title == "My Task")
        #expect(TaskEntity.typeDisplayRepresentation.name == "Task")
    }
}
