import Foundation

extension TaskService {
    enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidName
        case taskNotFound
        case projectNotFound
        case duplicateDisplayID
        case restoreRequiresAbandonedTask
        case milestoneProjectMismatch
        case milestoneNotOpen
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
            case .milestoneNotOpen:
                "The selected milestone is no longer open."
            case .invalidIdentifier(let field):
                "The supplied \(field) is not a valid task identifier."
            }
        }
    }
}
