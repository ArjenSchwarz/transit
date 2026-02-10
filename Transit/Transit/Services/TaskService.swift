//
//  TaskService.swift
//  Transit
//
//  Central service for all task mutations.
//

import Foundation
import SwiftData

@MainActor @Observable
final class TaskService {
    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    init(modelContext: ModelContext, displayIDAllocator: DisplayIDAllocator) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
    }

    /// Create a new task in Idea status.
    func createTask(
        name: String,
        description: String?,
        type: TaskType,
        project: Project,
        metadata: [String: String]?
    ) async throws -> TransitTask {
        // Try to allocate permanent ID, fall back to provisional if offline
        let permanentID: Int?
        do {
            permanentID = try await displayIDAllocator.allocateNextID()
        } catch {
            // Offline - use provisional
            permanentID = nil
        }

        let task = TransitTask(
            name: name,
            description: description,
            type: type,
            project: project,
            permanentDisplayId: permanentID,
            metadata: metadata
        )

        StatusEngine.initializeNewTask(task)
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    /// Change task status via any source (drag, detail picker, intent).
    func updateStatus(task: TransitTask, to newStatus: TaskStatus) throws {
        StatusEngine.applyTransition(task: task, to: newStatus)
        try modelContext.save()
    }

    /// Abandon a task from any status.
    func abandon(task: TransitTask) throws {
        StatusEngine.applyTransition(task: task, to: .abandoned)
        try modelContext.save()
    }

    /// Restore an abandoned task to Idea.
    func restore(task: TransitTask) throws {
        StatusEngine.applyTransition(task: task, to: .idea)
        try modelContext.save()
    }

    /// Find task by displayId for intent lookups.
    func findByDisplayID(_ displayId: Int) throws -> TransitTask? {
        let predicate = #Predicate<TransitTask> { $0.permanentDisplayId == displayId }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    /// Query tasks with optional filters for intent lookups.
    func queryTasks(predicate: Predicate<TransitTask>?) throws -> [TransitTask] {
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }
}
