import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TaskService: @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case invalidName
        case missingProject
        case taskNotFound
        case duplicateDisplayID
        case restoreRequiresAbandonedTask
    }

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    var context: ModelContext {
        modelContext
    }

    init(modelContext: ModelContext, displayIDAllocator: DisplayIDAllocator) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
    }

    func createTask(
        project: Project?,
        name: String,
        description: String? = nil,
        type: TaskType,
        metadata: [String: String]? = nil,
        now: Date = .now
    ) async throws -> TransitTask {
        guard let project else {
            throw Error.missingProject
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Error.invalidName
        }

        let task = TransitTask(
            name: trimmedName,
            description: normalizeOptionalText(description),
            status: .idea,
            type: type,
            creationDate: now,
            lastStatusChangeDate: now,
            completionDate: nil,
            metadata: metadata,
            project: project
        )

        StatusEngine.initializeNewTask(task, now: now)

        do {
            task.permanentDisplayId = try await displayIDAllocator.allocateNextID()
        } catch {
            task.permanentDisplayId = nil
        }

        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    func updateStatus(
        task: TransitTask,
        to newStatus: TaskStatus,
        now: Date = .now
    ) throws {
        StatusEngine.applyTransition(task: task, to: newStatus, now: now)
        try modelContext.save()
    }

    func abandon(task: TransitTask, now: Date = .now) throws {
        try updateStatus(task: task, to: .abandoned, now: now)
    }

    func restore(task: TransitTask, now: Date = .now) throws {
        guard task.status == .abandoned else {
            throw Error.restoreRequiresAbandonedTask
        }

        StatusEngine.applyTransition(task: task, to: .idea, now: now)
        try modelContext.save()
    }

    func findByDisplayID(_ displayID: Int) throws -> TransitTask {
        let predicate = #Predicate<TransitTask> { task in
            task.permanentDisplayId == displayID
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\TransitTask.creationDate)]
        )
        let tasks = try modelContext.fetch(descriptor)

        guard let first = tasks.first else {
            throw Error.taskNotFound
        }

        guard tasks.count == 1 else {
            throw Error.duplicateDisplayID
        }

        return first
    }

    private func normalizeOptionalText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
