import AppIntents
import Foundation

struct AddCommentIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource =
        "Transit: Add Comment"

    nonisolated(unsafe) static var description = IntentDescription(
        "Add a comment to a Transit task.",
        categoryName: "Tasks"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Task", description: "Display ID (e.g. 42) or UUID")
    var taskIdentifier: String

    @Parameter(title: "Comment")
    var commentText: String

    @Parameter(title: "Author Name")
    var authorName: String

    @Parameter(title: "Agent Comment", default: false)
    var isAgent: Bool

    @Dependency
    var taskService: TaskService

    @Dependency
    var commentService: CommentService

    @MainActor
    func perform() async throws -> some IntentResult {
        try Self.execute(
            taskIdentifier: taskIdentifier,
            commentText: commentText,
            authorName: authorName,
            isAgent: isAgent,
            services: Services(taskService: taskService, commentService: commentService)
        )
        return .result()
    }

    // MARK: - Logic (testable without @Dependency)

    struct Services {
        let taskService: TaskService
        let commentService: CommentService
    }

    @MainActor
    static func execute(
        taskIdentifier: String,
        commentText: String,
        authorName: String,
        isAgent: Bool,
        services: Services,
        persistence: PersistenceAvailability = .shared
    ) throws {
        // Refuse to write while the in-memory fallback container is active [T-1836].
        guard !persistence.isFallbackStorageActive else {
            throw VisualIntentError.persistenceUnavailable
        }

        let task: TransitTask
        do {
            task = try services.taskService.resolveTask(from: taskIdentifier)
        } catch TaskService.Error.duplicateDisplayID {
            // The identifier matches several tasks, so the comment has no unambiguous
            // home. Report it as a duplicate (INTERNAL_ERROR) rather than "not found",
            // which would hide that the store needs display-ID maintenance. [T-1837]
            throw VisualIntentError.duplicateIdentifier(
                "More than one task uses identifier '\(taskIdentifier)'."
            )
        } catch {
            throw VisualIntentError.taskNotFound(
                "No task matching '\(taskIdentifier)'."
            )
        }

        let trimmed = commentText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VisualIntentError.invalidInput("Comment text is empty.")
        }
        let trimmedAuthor = authorName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthor.isEmpty else {
            throw VisualIntentError.invalidInput("Author name is empty.")
        }

        try services.commentService.addComment(
            to: task,
            content: trimmed,
            authorName: trimmedAuthor,
            isAgent: isAgent
        )
    }
}
