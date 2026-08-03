import Foundation
import SwiftData

/// Coordinates task creation, status changes, and lookups. Uses StatusEngine
/// for all status transitions and DisplayIDAllocator for display ID assignment.
@MainActor @Observable
// swiftlint:disable:next type_body_length
final class TaskService {

    enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidName
        case taskNotFound
        case projectNotFound
        case duplicateDisplayID
        case restoreRequiresAbandonedTask
        case milestoneProjectMismatch
        /// Identifier key present but malformed; field name surfaces a field-specific INVALID_INPUT [T-808]
        case invalidIdentifier(field: String)

        var errorDescription: String? {
            switch self {
            case .invalidName:
                "Task name cannot be empty."
            case .taskNotFound:
                "The specified task could not be found."
            case .projectNotFound:
                "The selected project could not be found."
            case .duplicateDisplayID:
                "A duplicate task identifier was detected."
            case .restoreRequiresAbandonedTask:
                "Only abandoned tasks can be restored."
            case .milestoneProjectMismatch:
                "Milestone and task must belong to the same project."
            case .invalidIdentifier(let field):
                "The supplied \(field) is not a valid task identifier."
            }
        }
    }

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator
    private let createSave: (ModelContext) throws -> Void
    private let statusSave: (ModelContext) throws -> Void

    /// Display IDs feeding the allocator's collision guard. Production unions a
    /// transient committed-store read with the live main-context values; the
    /// injectable live fetcher lets tests simulate stale or unreadable registered
    /// state without replacing the committed-store read (T-1621, T-1939).
    private let usedDisplayIDs: UsedDisplayIDs

    init(
        modelContext: ModelContext,
        displayIDAllocator: DisplayIDAllocator,
        fetcher: (any ModelFetching)? = nil,
        createSave: @escaping (ModelContext) throws -> Void = { try $0.save() },
        statusSave: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
        self.usedDisplayIDs = UsedDisplayIDs(
            modelContext: modelContext,
            liveFetcher: fetcher ?? modelContext
        )
        self.createSave = createSave
        self.statusSave = statusSave
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
        metadata: [String: String]? = nil,
        priority: TaskPriority = .medium,
        milestone: Milestone? = nil
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
            metadata: metadata,
            priority: priority,
            milestone: milestone
        )
    }

    /// Creates a new task in `.idea` status. The optional milestone is validated
    /// and attached before insertion so the aggregate is persisted in one save.
    /// Attempts to allocate a permanent display ID from CloudKit; falls back to
    /// provisional on failure. `createSave` is injectable for surface-level
    /// persistence failure tests.
    @discardableResult
    func createTask(
        name: String,
        description: String?,
        type: TaskType,
        project: Project,
        metadata: [String: String]? = nil,
        priority: TaskPriority = .medium,
        milestone: Milestone? = nil,
        save: ((ModelContext) throws -> Void)? = nil
    ) async throws -> TransitTask {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Error.invalidName
        }

        // Keep this validation at the aggregate boundary even though automation
        // surfaces pre-validate resolved milestones: direct UI and future callers
        // must not allocate an ID or insert a cross-project relationship.
        if let milestone, milestone.project?.id != project.id {
            throw Error.milestoneProjectMismatch
        }

        let displayID: DisplayID
        do {
            // Pass a closure so the set of display IDs already committed locally
            // is snapshotted inside the allocation gate — fresh relative to any
            // concurrent create that committed just before us — so the allocator
            // never hands back an in-use ID even against a stale counter read
            // (T-1395).
            let id = try await displayIDAllocator.allocateNextID(excluding: { try self.usedDisplayIDs.tasks() })
            displayID = .permanent(id)
        } catch let error as CancellationError {
            // The allocation gate propagates CancellationError when this caller is
            // cancelled while waiting for an ID (T-1395). Cancellation must abort the
            // create before any insert/save so a cancelled request never mutates
            // persistent state — only genuine CloudKit/offline failures fall back to
            // a provisional ID (T-1426).
            throw error
        } catch DisplayIDAllocator.Error.usedIDLookupFailed(let description) {
            // The local store could not be read, so the collision guard never ran.
            // That is not the offline condition provisional IDs exist for, and a
            // provisional ID would hide a broken store behind a normal-looking
            // create — surface it instead (T-1621).
            throw DisplayIDAllocator.Error.usedIDLookupFailed(description: description)
        } catch {
            displayID = .provisional
        }

        // Counter stores are not required to cooperate with Swift cancellation.
        // Re-check after allocation handling and immediately before constructing
        // and inserting the model so a successfully allocated ID cannot turn a
        // cancelled operation into a persisted task (T-1765).
        try Task.checkCancellation()

        let task = TransitTask(
            name: trimmedName,
            description: description,
            type: type,
            project: project,
            displayID: displayID,
            metadata: metadata,
            priority: priority
        )
        StatusEngine.initializeNewTask(task)
        task.milestone = milestone

        try modelContext.insertOrDelete(task, save: save ?? createSave)
        return task
    }

    // MARK: - Status Changes

    /// Transitions a task to a new status via StatusEngine.
    /// When comment parameters are provided, creates a comment atomically
    /// in the same save operation and returns that exact comment.
    /// Same-status updates are treated as no-ops so callers can safely retry
    /// or re-send the current status without mutating timestamps.
    /// Comments are always persisted regardless of whether the status changed.
    @discardableResult
    func updateStatus(
        task: TransitTask,
        to newStatus: TaskStatus,
        comment: String? = nil,
        commentAuthor: String? = nil,
        commentService: CommentService? = nil,
        save: Bool = true
    ) throws -> Comment? {
        let statusChanged = task.status != newStatus
        let hasComment = comment.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        guard statusChanged || hasComment else { return nil }

        var createdComment: Comment?
        do {
            if statusChanged {
                StatusEngine.applyTransition(task: task, to: newStatus)
            }
            if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let commentAuthor, let commentService {
                createdComment = try commentService.addComment(
                    to: task,
                    content: comment,
                    authorName: commentAuthor,
                    isAgent: true,
                    save: nil
                )
            }
            if save {
                try statusSave(modelContext)
            }
        } catch {
            // A status update is an update, but its optional comment is a create.
            // Delete the inserted model before rolling back so a failed save cannot
            // leave a ghost comment that a later unrelated save would persist.
            if let createdComment {
                modelContext.delete(createdComment)
            }
            modelContext.safeRollback()
            throw error
        }
        return createdComment
    }

    /// Moves a task to `.abandoned` status.
    func abandon(task: TransitTask) throws {
        StatusEngine.applyTransition(task: task, to: .abandoned)
        try modelContext.saveOrRollback()
    }

    /// Restores an abandoned task back to `.idea` status.
    func restore(task: TransitTask) throws {
        guard task.status == .abandoned else {
            throw Error.restoreRequiresAbandonedTask
        }
        StatusEngine.applyTransition(task: task, to: .idea)
        try modelContext.saveOrRollback()
    }

    // MARK: - Project Management

    /// Changes a task's project. Clears milestone before the change to enforce
    /// Decision 6 (milestones are scoped to a project).
    func changeProject(task: TransitTask, to newProject: Project, save: Bool = true) throws {
        if task.project?.id != newProject.id {
            task.milestone = nil
        }
        task.project = newProject

        try modelContext.saveOrRollback(save: save)
    }

    // MARK: - Resolution

    /// Resolves a task from a string identifier (display ID as integer string, or UUID string).
    func resolveTask(from identifier: String) throws -> TransitTask {
        if let displayId = Int(identifier) {
            return try findByDisplayID(displayId)
        } else if let uuid = UUID(uuidString: identifier) {
            return try findByID(uuid)
        }
        throw Error.taskNotFound
    }

    /// Resolves a task from a dictionary with optional "displayId" or "taskId" keys.
    /// Validates key presence separately from value parsing so a present-but-malformed
    /// key surfaces an `invalidIdentifier(field:)` error instead of silently falling
    /// back to the other key or to `taskNotFound`. [T-808]
    func resolveTask(from dict: [String: Any]) throws -> TransitTask {
        if dict["displayId"] != nil {
            guard let displayId = IntentHelpers.parseIntValue(dict["displayId"]) else {
                throw Error.invalidIdentifier(field: "displayId")
            }
            return try findByDisplayID(displayId)
        }
        if dict["taskId"] != nil {
            guard let taskIdStr = dict["taskId"] as? String,
                  let uuid = UUID(uuidString: taskIdStr) else {
                throw Error.invalidIdentifier(field: "taskId")
            }
            return try findByID(uuid)
        }
        throw Error.taskNotFound
    }

    // MARK: - Field Updates

    /// Update task fields. Only non-nil parameters are applied.
    ///
    /// `description` is special-cased: passing `nil` means "no change" so the
    /// stored description survives, while passing `clearDescription: true`
    /// without a `description` value explicitly nils out `taskDescription`.
    /// An explicit non-nil `description` always wins, even when
    /// `clearDescription` is also `true`. Mirrors
    /// `MilestoneService.updateMilestone` (T-854).
    func updateTask(
        _ task: TransitTask,
        name: String? = nil,
        description: String? = nil,
        clearDescription: Bool = false,
        type: TaskType? = nil,
        metadata: [String: String]? = nil,
        priority: TaskPriority? = nil,
        save: Bool = true
    ) throws {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw Error.invalidName
            }
            task.name = trimmed
        }
        if let description {
            task.taskDescription = description
        } else if clearDescription {
            task.taskDescription = nil
        }
        if let type { task.type = type }
        if let metadata { task.metadata = metadata }
        if let priority { task.priority = priority }

        try modelContext.saveOrRollback(save: save)
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

    // MARK: - Fetch

    /// Fetches all tasks from the model context.
    func fetchAllTasks() throws -> [TransitTask] {
        try modelContext.fetch(FetchDescriptor<TransitTask>())
    }

    /// Fetches terminal (done/abandoned) tasks with project relationship prefetched.
    func fetchTerminalTasks() throws -> [TransitTask] {
        let predicate = #Predicate<TransitTask> {
            $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
        }
        var descriptor = FetchDescriptor<TransitTask>(predicate: predicate)
        descriptor.relationshipKeyPathsForPrefetching = [\.project]
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Delete

    /// Deletes a task and optionally saves the context.
    func deleteTask(_ task: TransitTask, save: Bool = true) throws {
        modelContext.delete(task)
        try modelContext.saveOrRollback(save: save)
    }

    // MARK: - Persistence

    /// Saves the model context. Rolls back on failure.
    func save() throws {
        try modelContext.saveOrRollback()
    }

    /// Reverts in-memory mutations on the model context. Used by handlers to
    /// undo partial changes when a multi-step update (e.g. updateTask followed
    /// by setMilestone) throws between steps and the caller wants to abandon
    /// the transaction before save. [T-650]
    func rollback() {
        modelContext.safeRollback()
    }
}
