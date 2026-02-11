import Foundation

enum VisualIntentError: LocalizedError {
    case noProjects
    case invalidInput(String)
    case invalidDate(String)
    case projectNotFound(String)
    case taskNotFound(String)
    case taskCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProjects:
            "No projects exist. Create a project in Transit first."
        case .invalidInput(let hint):
            "Invalid input: \(hint)"
        case .invalidDate(let hint):
            "Invalid date: \(hint)"
        case .projectNotFound(let hint):
            "Project not found: \(hint)"
        case .taskNotFound(let hint):
            "Task not found: \(hint)"
        case .taskCreationFailed(let hint):
            "Task creation failed: \(hint)"
        }
    }

    var failureReason: String? {
        switch self {
        case .noProjects:
            "Transit requires at least one project to create tasks."
        case .invalidInput:
            "The provided input is missing required fields or contains invalid data."
        case .invalidDate:
            "The date format is incorrect or the date range is invalid."
        case .projectNotFound:
            "The selected project no longer exists in the database."
        case .taskNotFound:
            "The specified task could not be found."
        case .taskCreationFailed:
            "An unexpected error occurred while creating the task."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noProjects:
            "Open Transit and create a project before using this Shortcut."
        case .invalidInput:
            "Check that all required fields are filled in correctly."
        case .invalidDate:
            "Verify the date format (YYYY-MM-DD) or select a valid date range."
        case .projectNotFound:
            "Select a different project or create a new one in the app."
        case .taskNotFound:
            "The task may have been deleted. Try searching for it in the app."
        case .taskCreationFailed:
            "Check that the app has sufficient storage and try again. If the problem persists, restart the app."
        }
    }
}
