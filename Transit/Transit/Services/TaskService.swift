import Foundation
import SwiftData

/// Coordinates task creation, status changes, and lookups. Uses StatusEngine
/// for all status transitions and DisplayIDAllocator for display ID assignment.
@MainActor @Observable
final class TaskService {

    enum Error: Swift.Error, Equatable {
        case invalidName
        case taskNotFound
        case projectNotFound
        case duplicateDisplayID
        case restoreRequiresAbandonedTask
    }

    let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    init(modelContext: ModelContext, displayIDAllocator: DisplayIDAllocator) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
    }

    // MARK: - Task Creation

    /// Creates a new task in `.idea` status, looking up the project by UUID.
    /// Fetches the project from the model context, then delegates to the
    /// primary `createTask` overload.
    @discardableResult
    func createTask(
        name: String,
        description: String?,
        type: TaskType,
        projectID: UUID,
        metadata: [String: String]? = nil
    ) async throws -> TransitTask {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectID }
        )
        guard let project = try modelContext.fetch(descriptor).first else {
            throw Error.projectNotFound
        }
        return try await createTask(
            name: name,
            description: description,
            type: type,
            project: project,
            metadata: metadata
        )
    }

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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Error.invalidName
        }

        let displayID: DisplayID
        do {
            let id = try await displayIDAllocator.allocateNextID()
            displayID = .permanent(id)
        } catch {
            displayID = .provisional
        }

        let task = TransitTask(
            name: trimmedName,
            description: description,
            type: type,
            project: project,
            displayID: displayID,
            metadata: metadata
        )
        StatusEngine.initializeNewTask(task)

        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    // MARK: - Status Changes

    /// Transitions a task to a new status via StatusEngine.
    /// When comment parameters are provided, creates a comment atomically
    /// in the same save operation.
    func updateStatus(
        task: TransitTask,
        to newStatus: TaskStatus,
        comment: String? = nil,
        commentAuthor: String? = nil,
        commentService: CommentService? = nil
    ) throws {
        StatusEngine.applyTransition(task: task, to: newStatus)

        do {
            if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let commentAuthor, let commentService {
                try commentService.addComment(
                    to: task,
                    content: comment,
                    authorName: commentAuthor,
                    isAgent: true,
                    save: false
                )
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Moves a task to `.abandoned` status.
    func abandon(task: TransitTask) throws {
        StatusEngine.applyTransition(task: task, to: .abandoned)
        try modelContext.save()
    }

    /// Restores an abandoned task back to `.idea` status.
    func restore(task: TransitTask) throws {
        guard task.status == .abandoned else {
            throw Error.restoreRequiresAbandonedTask
        }
        StatusEngine.applyTransition(task: task, to: .idea)
        try modelContext.save()
    }

    // MARK: - Lookup

    /// Finds a task by its UUID. Throws on not-found.
    func findByID(_ id: UUID) throws -> TransitTask {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == id }
        )
        guard let task = try modelContext.fetch(descriptor).first else {
            throw Error.taskNotFound
        }
        return task
    }

    /// Finds a task by its permanent display ID. Throws on not-found or duplicates.
    func findByDisplayID(_ displayId: Int) throws -> TransitTask {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId == displayId }
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
}
