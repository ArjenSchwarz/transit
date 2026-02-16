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
        let task = try resolveTask()

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

        try commentService.addComment(
            to: task,
            content: trimmed,
            authorName: trimmedAuthor,
            isAgent: isAgent
        )

        return .result()
    }

    // MARK: - Private

    @MainActor
    private func resolveTask() throws -> TransitTask {
        if let displayId = Int(taskIdentifier) {
            do {
                return try taskService.findByDisplayID(displayId)
            } catch {
                throw VisualIntentError.taskNotFound(
                    "No task with display ID \(taskIdentifier)."
                )
            }
        } else if let uuid = UUID(uuidString: taskIdentifier) {
            do {
                return try taskService.findByID(uuid)
            } catch {
                throw VisualIntentError.taskNotFound(
                    "No task with ID \(taskIdentifier)."
                )
            }
        } else {
            throw VisualIntentError.invalidInput(
                "'\(taskIdentifier)' is not a valid display ID or UUID."
            )
        }
    }
}
