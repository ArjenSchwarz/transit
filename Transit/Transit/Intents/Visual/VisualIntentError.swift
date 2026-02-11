import Foundation

enum VisualIntentError: LocalizedError, Equatable {
    case noProjects
    case invalidInput(String)
    case invalidDate(String)
    case projectNotFound(String)
    case taskNotFound(String)
    case taskCreationFailed(String)

    var code: String {
        switch self {
        case .noProjects:
            "NO_PROJECTS"
        case .invalidInput:
            "INVALID_INPUT"
        case .invalidDate:
            "INVALID_DATE"
        case .projectNotFound:
            "PROJECT_NOT_FOUND"
        case .taskNotFound:
            "TASK_NOT_FOUND"
        case .taskCreationFailed:
            "TASK_CREATION_FAILED"
        }
    }

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
            "At least one project is required to create a task."
        case .invalidInput:
            "The provided parameters are missing required values or contain invalid data."
        case .invalidDate:
            "The provided date format or date range is invalid."
        case .projectNotFound:
            "The selected project could not be found in Transit."
        case .taskNotFound:
            "The specified task could not be found in Transit."
        case .taskCreationFailed:
            "Transit could not create the task due to an unexpected failure."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noProjects:
            "Open Transit and create a project before running this shortcut again."
        case .invalidInput:
            "Check your inputs and try again."
        case .invalidDate:
            "Use YYYY-MM-DD dates or a supported relative date option."
        case .projectNotFound:
            "Select a different project or create one in Transit."
        case .taskNotFound:
            "Verify the task identifier and try again."
        case .taskCreationFailed:
            "Try again in a moment. If the issue persists, reopen Transit."
        }
    }
}
