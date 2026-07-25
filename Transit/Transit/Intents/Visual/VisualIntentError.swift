import Foundation

enum VisualIntentError: LocalizedError, Equatable {
    case noProjects
    case invalidInput(String)
    case invalidDate(String)
    case projectNotFound(String)
    case taskNotFound(String)
    case taskCreationFailed(String)
    /// The supplied identifier matches more than one task. CloudKit cannot enforce unique
    /// display IDs, so this is store corruption to repair with display-ID maintenance, not a
    /// bad request. Uses INTERNAL_ERROR to match the JSON intents' code for the same
    /// condition [T-1837].
    case duplicateIdentifier(String)
    /// Transit is running on the in-memory fallback container, so the write would be lost on
    /// restart. Uses INTERNAL_ERROR to match the JSON intents' code for the same condition
    /// [T-1818, T-1836].
    case persistenceUnavailable

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
        case .duplicateIdentifier:
            "INTERNAL_ERROR"
        case .persistenceUnavailable:
            "INTERNAL_ERROR"
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
        case .duplicateIdentifier(let hint):
            "Duplicate task identifier: \(hint)"
        case .persistenceUnavailable:
            PersistenceAvailability.unavailableHint
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
        case .duplicateIdentifier:
            "Several Transit tasks share the identifier that was supplied."
        case .persistenceUnavailable:
            "Transit could not open its database and is using temporary storage."
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
        case .duplicateIdentifier:
            "Run display ID maintenance in Transit to repair the duplicates, then try again."
        case .persistenceUnavailable:
            "Restart Transit and check available device storage, then try again."
        }
    }
}
