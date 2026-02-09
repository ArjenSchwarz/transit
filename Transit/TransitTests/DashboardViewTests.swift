//
//  DashboardViewTests.swift
//  TransitTests
//
//  Tests for dashboard column filtering, sorting, and project filter logic.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DashboardViewTests {
    @Test("Tasks are grouped by column")
    func testColumnGrouping() throws {
        let context = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let ideaTask = makeTestTask(name: "Idea", status: .idea, project: project, context: context)
        let planningTask = makeTestTask(name: "Planning", status: .planning, project: project, context: context)
        let doneTask = makeTestTask(name: "Done", status: .done, project: project, context: context)

        let tasks = [ideaTask, planningTask, doneTask]
        let grouped = Dictionary(grouping: tasks) { $0.status.column }

        #expect(grouped[.idea]?.count == 1)
        #expect(grouped[.planning]?.count == 1)
        #expect(grouped[.doneAbandoned]?.count == 1)
    }

    @Test("Done/Abandoned column filters by 48-hour cutoff")
    func test48HourCutoff() throws {
        let context = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let now = Date.now
        let cutoff = now.addingTimeInterval(-48 * 60 * 60)

        // Recent done task (within 48 hours)
        let recentTask = makeTestTask(name: "Recent", status: .done, project: project, context: context)
        recentTask.completionDate = now.addingTimeInterval(-24 * 60 * 60)

        // Old done task (beyond 48 hours)
        let oldTask = makeTestTask(name: "Old", status: .done, project: project, context: context)
        oldTask.completionDate = now.addingTimeInterval(-72 * 60 * 60)

        let tasks = [recentTask, oldTask]
        let filtered = tasks.filter { task in
            if task.status.isTerminal {
                return (task.completionDate ?? now) > cutoff
            }
            return true
        }

        #expect(filtered.count == 1)
        #expect(filtered.first?.name == "Recent")
    }

    @Test("Done tasks sort before abandoned tasks")
    func testDoneBeforeAbandoned() throws {
        let context = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let doneTask = makeTestTask(name: "Done", status: .done, project: project, context: context)
        let abandonedTask = makeTestTask(name: "Abandoned", status: .abandoned, project: project, context: context)

        let tasks = [abandonedTask, doneTask]
        let sorted = tasks.sorted { first, second in
            if (first.status == .abandoned) != (second.status == .abandoned) {
                return second.status == .abandoned
            }
            return first.lastStatusChangeDate > second.lastStatusChangeDate
        }

        #expect(sorted.first?.name == "Done")
        #expect(sorted.last?.name == "Abandoned")
    }

    @Test("Handoff tasks sort first within column")
    func testHandoffSortFirst() throws {
        let context = makeTestContext()
        let project = Project(
            name: "Test",
            description: "",
            gitRepo: nil,
            color: .red
        )
        context.insert(project)

        let normalTask = makeTestTask(
            name: "Normal",
            status: .spec,
            project: project,
            context: context
        )
        let handoffTask = makeTestTask(
            name: "Handoff",
            status: .readyForImplementation,
            project: project,
            context: context
        )

        let tasks = [normalTask, handoffTask]
        let sorted = tasks.sorted { first, second in
            if first.status.isHandoff != second.status.isHandoff {
                return first.status.isHandoff
            }
            return first.lastStatusChangeDate > second.lastStatusChangeDate
        }

        #expect(sorted.first?.name == "Handoff")
        #expect(sorted.last?.name == "Normal")
    }

    @Test("Project filter includes only selected projects")
    func testProjectFilter() throws {
        let context = makeTestContext()
        let project1 = Project(name: "Project 1", description: "", gitRepo: nil, color: .red)
        let project2 = Project(name: "Project 2", description: "", gitRepo: nil, color: .green)
        context.insert(project1)
        context.insert(project2)

        let task1 = makeTestTask(name: "Task 1", status: .idea, project: project1, context: context)
        let task2 = makeTestTask(name: "Task 2", status: .idea, project: project2, context: context)

        let allTasks = [task1, task2]
        let selectedProjectIDs: Set<UUID> = [project1.id]

        let filtered = allTasks.filter { task in
            guard let projectId = task.project?.id else { return false }
            return selectedProjectIDs.contains(projectId)
        }

        #expect(filtered.count == 1)
        #expect(filtered.first?.name == "Task 1")
    }

    @Test("Empty project filter shows all tasks")
    func testEmptyFilterShowsAll() throws {
        let context = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let task1 = makeTestTask(name: "Task 1", status: .idea, project: project, context: context)
        let task2 = makeTestTask(name: "Task 2", status: .planning, project: project, context: context)

        let allTasks = [task1, task2]
        let selectedProjectIDs: Set<UUID> = []

        let filtered: [TransitTask]
        if selectedProjectIDs.isEmpty {
            filtered = allTasks.filter { $0.project != nil }
        } else {
            filtered = allTasks.filter { task in
                guard let projectId = task.project?.id else { return false }
                return selectedProjectIDs.contains(projectId)
            }
        }

        #expect(filtered.count == 2)
    }

    @Test("Tasks without completionDate are treated as just-completed")
    func testMissingCompletionDate() throws {
        let context = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let now = Date.now
        let cutoff = now.addingTimeInterval(-48 * 60 * 60)

        // Done task without completionDate (defensive case)
        let task = makeTestTask(name: "Done", status: .done, project: project, context: context)
        task.completionDate = nil

        let filtered = [task].filter { task in
            if task.status.isTerminal {
                return (task.completionDate ?? now) > cutoff
            }
            return true
        }

        #expect(filtered.count == 1)
    }

    // MARK: - Test Helpers

    private func makeTestContext() -> ModelContext {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func makeTestTask(
        name: String,
        status: TaskStatus,
        project: Project,
        context: ModelContext
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: nil,
            metadata: nil
        )
        task.status = status
        context.insert(task)
        return task
    }
}
