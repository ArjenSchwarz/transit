import Foundation
import SwiftData
@testable import Transit

@MainActor
func makeReportTestContext() throws -> ModelContext {
    let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
    let config = ModelConfiguration(
        "ReportLogicTests-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

/// Creates a task, inserts it into the context, and transitions it to a terminal status.
@MainActor
@discardableResult
func makeTerminalTask(
    name: String,
    project: Project,
    displayID: DisplayID = .provisional,
    status: TaskStatus = .done,
    completionDate: Date,
    context: ModelContext
) -> TransitTask {
    let task = TransitTask(
        name: name,
        type: .feature,
        project: project,
        displayID: displayID
    )
    context.insert(task)
    StatusEngine.initializeNewTask(
        task, now: completionDate.addingTimeInterval(-100)
    )
    StatusEngine.applyTransition(task: task, to: status, now: completionDate)
    return task
}

/// Creates a task in a non-terminal status.
@MainActor
@discardableResult
func makeNonTerminalTask(
    name: String,
    project: Project,
    status: TaskStatus = .inProgress,
    context: ModelContext
) -> TransitTask {
    let task = TransitTask(
        name: name,
        type: .feature,
        project: project,
        displayID: .provisional
    )
    context.insert(task)
    StatusEngine.initializeNewTask(
        task, now: Date(timeIntervalSince1970: 1000)
    )
    if status != .idea {
        StatusEngine.applyTransition(
            task: task,
            to: status,
            now: Date(timeIntervalSince1970: 1100)
        )
    }
    return task
}

@MainActor
func makeTestProject(name: String, context: ModelContext) -> Project {
    let project = Project(
        name: name,
        description: "",
        gitRepo: nil,
        colorHex: "#000000"
    )
    context.insert(project)
    return project
}

/// Fixed reference date: Wednesday Feb 18, 2026 at 14:00:00 local time.
var reportTestNow: Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 2
    components.day = 18
    components.hour = 14
    components.minute = 0
    components.second = 0
    return Calendar.current.date(from: components)!
}
