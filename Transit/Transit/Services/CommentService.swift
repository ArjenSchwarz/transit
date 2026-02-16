import Foundation
import SwiftData

@MainActor @Observable
final class CommentService {

    enum Error: Swift.Error, Equatable {
        case emptyContent
        case emptyAuthorName
        case commentNotFound
        case taskNotFound
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Creates a comment on a task. Validates content and authorName are
    /// non-empty after trimming whitespace.
    ///
    /// The task is re-fetched from this service's own `ModelContext` to avoid
    /// cross-context relationship issues (e.g. the view passes a task from
    /// `mainContext` but this service uses a separate context).
    ///
    /// When `save` is false, the caller is responsible for calling
    /// modelContext.save(). Used for atomic operations where multiple
    /// mutations must be saved together (e.g. status update + comment).
    @discardableResult
    func addComment(
        to task: TransitTask,
        content: String,
        authorName: String,
        isAgent: Bool,
        save: Bool = true
    ) throws -> Comment {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { throw Error.emptyContent }

        let trimmedAuthor = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthor.isEmpty else { throw Error.emptyAuthorName }

        // Resolve the task in this service's context to ensure the
        // relationship is established within a single ModelContext.
        let resolvedTask = try resolveTask(task)

        let comment = Comment(
            content: trimmedContent,
            authorName: trimmedAuthor,
            isAgent: isAgent,
            task: resolvedTask
        )
        modelContext.insert(comment)
        if save {
            try modelContext.save()
        }
        return comment
    }

    /// Deletes a comment permanently.
    func deleteComment(_ comment: Comment) throws {
        modelContext.delete(comment)
        try modelContext.save()
    }

    /// Fetches comments for a task, querying from the Comment side.
    /// Sorted by creationDate ascending, UUID as tiebreaker.
    func fetchComments(for taskID: UUID) throws -> [Comment] {
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.task?.id == taskID },
            sortBy: [
                SortDescriptor(\.creationDate, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns comment count for a task using fetchCount for efficiency.
    func commentCount(for taskID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.task?.id == taskID }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Private

    /// Re-fetches a task from this service's ModelContext by UUID.
    /// If the task is already registered in this context, returns it directly.
    private func resolveTask(_ task: TransitTask) throws -> TransitTask {
        if let registered = modelContext.registeredModel(for: task.persistentModelID) as TransitTask? {
            return registered
        }
        let taskID = task.id
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let resolved = try modelContext.fetch(descriptor).first else {
            throw Error.taskNotFound
        }
        return resolved
    }
}
