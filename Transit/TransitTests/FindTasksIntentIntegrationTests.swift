import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct FindTasksIntentIntegrationTests {
    private struct TaskSeed {
        let name: String
        let displayID: Int
        let status: TaskStatus
        let type: TaskType
        var completionDate: Date?
        let lastStatusChangeDate: Date
    }

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String) -> Project {
        let project = Project(name: name, description: "desc", gitRepo: nil, colorHex: "#0099FF")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        in context: ModelContext,
        project: Project,
        seed: TaskSeed
    ) -> TransitTask {
        let task = TransitTask(
            name: seed.name,
            type: seed.type,
            project: project,
            displayID: .permanent(seed.displayID)
        )
        StatusEngine.initializeNewTask(task)

        if seed.status != .idea {
            StatusEngine.applyTransition(task: task, to: seed.status)
        }

        if let completionDate = seed.completionDate {
            task.completionDate = completionDate
        }
        task.lastStatusChangeDate = seed.lastStatusChangeDate

        context.insert(task)
        return task
    }

    @Test func findTasksIntentReturnsTaskEntitiesWithExpectedFields() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "Integration")
        let now = Date.now

        let task = makeTask(
            in: context,
            project: project,
            seed: TaskSeed(
                name: "Find me",
                displayID: 42,
                status: .done,
                type: .documentation,
                completionDate: now,
                lastStatusChangeDate: now
            )
        )

        let entities = try FindTasksIntent.execute(
            filters: FindTasksIntent.Filters(
                type: .documentation,
                project: ProjectEntity.from(project),
                status: .done,
                completionDateFilter: .today,
                completionFromDate: nil,
                completionToDate: nil,
                lastStatusChangeDateFilter: .today,
                lastStatusChangeFromDate: nil,
                lastStatusChangeToDate: nil
            ),
            modelContext: context
        )

        #expect(entities.count == 1)
        let first = entities[0]
        #expect(first.taskId == task.id)
        #expect(first.displayId == 42)
        #expect(first.name == "Find me")
        #expect(first.status == TaskStatus.done.rawValue)
        #expect(first.type == TaskType.documentation.rawValue)
        #expect(first.projectId == project.id)
        #expect(first.projectName == project.name)
        #expect(first.completionDate != nil)
    }

    @Test func findTasksIntentReturnsEmptyArrayForNoMatchesWithoutThrowing() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "Integration")

        _ = makeTask(
            in: context,
            project: project,
            seed: TaskSeed(
                name: "Only task",
                displayID: 1,
                status: .idea,
                type: .feature,
                lastStatusChangeDate: .now
            )
        )

        let entities = try FindTasksIntent.execute(
            filters: FindTasksIntent.Filters(
                type: .bug,
                project: nil,
                status: nil,
                completionDateFilter: nil,
                completionFromDate: nil,
                completionToDate: nil,
                lastStatusChangeDateFilter: nil,
                lastStatusChangeFromDate: nil,
                lastStatusChangeToDate: nil
            ),
            modelContext: context
        )

        #expect(entities.isEmpty)
    }
}
