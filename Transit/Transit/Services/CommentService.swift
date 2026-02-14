import Foundation
import SwiftData

@MainActor @Observable
final class CommentService {

    enum Error: Swift.Error, Equatable {
        case emptyContent
        case emptyAuthorName
        case commentNotFound
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Creates a comment on a task. Validates content and authorName are
    /// non-empty after trimming whitespace.
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

        let comment = Comment(
            content: trimmedContent,
            authorName: trimmedAuthor,
            isAgent: isAgent,
            task: task
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
}
