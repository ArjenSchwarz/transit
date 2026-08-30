import Foundation

// MARK: - Errors

extension MilestoneService {

    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidName
        case milestoneNotFound
        case projectNotFound
        case duplicateName
        case ambiguousName
        case duplicateDisplayID
        case projectRequired
        case projectMismatch

        var errorDescription: String? {
            switch self {
            case .invalidName:
                "Milestone name cannot be empty."
            case .milestoneNotFound:
                "The specified milestone could not be found."
            case .projectNotFound:
                "The selected project could not be found."
            case .duplicateName:
                "A milestone with this name already exists in the project."
            case .ambiguousName:
                "Multiple milestones with this name exist in the project."
            case .duplicateDisplayID:
                "A duplicate milestone identifier was detected."
            case .projectRequired:
                "Task must belong to a project before assigning a milestone."
            case .projectMismatch:
                "Milestone and task must belong to the same project."
            }
        }
    }
}
