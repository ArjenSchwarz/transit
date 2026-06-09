import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TransitTaskPriorityTests {

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    // MARK: - Default

    @Test func defaultPriorityRawValueIsMedium() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)

        #expect(task.priorityRawValue == "medium")
        #expect(task.priority == .medium)
    }

    // MARK: - Accessor fallback (effective-priority invariant)

    @Test func emptyRawValueReadsAsMedium() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)

        task.priorityRawValue = ""
        #expect(task.priority == .medium)
    }

    @Test func unrecognizedRawValueReadsAsMedium() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)

        task.priorityRawValue = "urgent"
        #expect(task.priority == .medium)
    }

    // MARK: - Setter

    @Test func setterWritesRawValue() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)

        task.priority = .high
        #expect(task.priorityRawValue == "high")

        task.priority = .low
        #expect(task.priorityRawValue == "low")
    }

    // MARK: - Init param

    @Test func initParamSetsPriorityRawValue() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let task = TransitTask(
            name: "Task", type: .feature, project: project, displayID: .provisional, priority: .high
        )

        #expect(task.priorityRawValue == "high")
        #expect(task.priority == .high)
    }
}
