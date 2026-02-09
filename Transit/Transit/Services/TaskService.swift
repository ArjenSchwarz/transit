import Foundation
import SwiftData

/// Coordinates task creation, status changes, and lookups. Uses StatusEngine
/// for all status transitions and DisplayIDAllocator for display ID assignment.
@MainActor @Observable
final class TaskService {

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    init(modelContext: ModelContext, displayIDAllocator: DisplayIDAllocator) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
    }

    // MARK: - Task Creation

    /// Creates a new task in `.idea` status. Attempts to allocate a permanent
    /// display ID from CloudKit; falls back to provisional on failure.
    @discardableResult
    func createTask(
        name: String,
        description: String?,
        type: TaskType,
        project: Project,
        metadata: [String: String]? = nil
    ) async throws -> TransitTask {
        let displayID: DisplayID
        do {
            let id = try await displayIDAllocator.allocateNextID()
            displayID = .permanent(id)
        } catch {
            displayID = .provisional
        }

        let task = TransitTask(
            name: name,
            description: description,
            type: type,
            project: project,
            displayID: displayID,
            metadata: metadata
        )
        StatusEngine.initializeNewTask(task)

        modelContext.insert(task)
        return task
    }

    // MARK: - Status Changes

    /// Transitions a task to a new status via StatusEngine.
    func updateStatus(task: TransitTask, to newStatus: TaskStatus) {
        StatusEngine.applyTransition(task: task, to: newStatus)
    }

    /// Moves a task to `.abandoned` status.
    func abandon(task: TransitTask) {
        StatusEngine.applyTransition(task: task, to: .abandoned)
    }

    /// Restores an abandoned or done task back to `.idea` status.
    func restore(task: TransitTask) {
        StatusEngine.applyTransition(task: task, to: .idea)
    }

    // MARK: - Lookup

    /// Finds a task by its permanent display ID.
    func findByDisplayID(_ displayId: Int) -> TransitTask? {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId == displayId }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
