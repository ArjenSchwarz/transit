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
    private var taskService: TaskService

    @Dependency
    private var commentService: CommentService

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
        services: Services
    ) throws {
        let task = try resolveTask(
            identifier: taskIdentifier, taskService: services.taskService
        )

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

    // MARK: - Private

    @MainActor
    private static func resolveTask(
        identifier: String, taskService: TaskService
    ) throws -> TransitTask {
        if let displayId = Int(identifier) {
            do {
                return try taskService.findByDisplayID(displayId)
            } catch {
                throw VisualIntentError.taskNotFound(
                    "No task with display ID \(identifier)."
                )
            }
        } else if let uuid = UUID(uuidString: identifier) {
            do {
                return try taskService.findByID(uuid)
            } catch {
                throw VisualIntentError.taskNotFound(
                    "No task with ID \(identifier)."
                )
            }
        } else {
            throw VisualIntentError.invalidInput(
                "'\(identifier)' is not a valid display ID or UUID."
            )
        }
    }
}
