//
//  DragDropTests.swift
//  TransitTests
//
//  Tests for drag-and-drop status mapping and completionDate handling.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DragDropTests {
    @Test("Drag to Done/Abandoned column sets status to Done")
    func testDragToDoneAbandonedSetsDone() throws {
        let context = makeTestContext()
        let taskService = TaskService(modelContext: context)
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let task = makeTestTask(name: "Task", status: .inProgress, project: project, context: context)

        try taskService.updateStatus(task: task, to: .done)

        #expect(task.status == .done)
        #expect(task.completionDate != nil)
    }

    @Test("Drag to non-terminal column uses primaryStatus")
    func testDragToNonTerminalUsesPrimaryStatus() throws {
        let context = makeTestContext()
        let taskService = TaskService(modelContext: context)
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let task = makeTestTask(name: "Task", status: .idea, project: project, context: context)

        try taskService.updateStatus(task: task, to: .planning)

        #expect(task.status == .planning)
        #expect(task.completionDate == nil)
    }

    @Test("Backward drag is allowed")
    func testBackwardDragAllowed() throws {
        let context = makeTestContext()
        let taskService = TaskService(modelContext: context)
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let task = makeTestTask(name: "Task", status: .inProgress, project: project, context: context)

        try taskService.updateStatus(task: task, to: .planning)

        #expect(task.status == .planning)
    }

    @Test("Drag from Done clears completionDate")
    func testDragFromDoneClearsCompletionDate() throws {
        let context = makeTestContext()
        let taskService = TaskService(modelContext: context)
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let task = makeTestTask(name: "Task", status: .done, project: project, context: context)
        task.completionDate = Date.now

        try taskService.updateStatus(task: task, to: .inProgress)

        #expect(task.status == .inProgress)
        #expect(task.completionDate == nil)
    }

    @Test("Drag from Abandoned clears completionDate")
    func testDragFromAbandonedClearsCompletionDate() throws {
        let context = makeTestContext()
        let taskService = TaskService(modelContext: context)
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .red)
        context.insert(project)

        let task = makeTestTask(name: "Task", status: .abandoned, project: project, context: context)
        task.completionDate = Date.now

        try taskService.updateStatus(task: task, to: .idea)

        #expect(task.status == .idea)
        #expect(task.completionDate == nil)
    }

    @Test("DashboardColumn primaryStatus mapping")
    func testPrimaryStatusMapping() {
        #expect(DashboardColumn.idea.primaryStatus == .idea)
        #expect(DashboardColumn.planning.primaryStatus == .planning)
        #expect(DashboardColumn.spec.primaryStatus == .spec)
        #expect(DashboardColumn.inProgress.primaryStatus == .inProgress)
        #expect(DashboardColumn.doneAbandoned.primaryStatus == .done)
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
