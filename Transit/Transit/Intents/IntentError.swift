import Foundation

nonisolated enum IntentError {
    case taskNotFound(hint: String)
    case projectNotFound(hint: String)
    case ambiguousProject(hint: String)
    case invalidStatus(hint: String)
    case invalidType(hint: String)
    case invalidInput(hint: String)
    case milestoneNotFound(hint: String)
    case duplicateMilestoneName(hint: String)
    case milestoneProjectMismatch(hint: String)

    var code: String {
        switch self {
        case .taskNotFound: "TASK_NOT_FOUND"
        case .projectNotFound: "PROJECT_NOT_FOUND"
        case .ambiguousProject: "AMBIGUOUS_PROJECT"
        case .invalidStatus: "INVALID_STATUS"
        case .invalidType: "INVALID_TYPE"
        case .invalidInput: "INVALID_INPUT"
        case .milestoneNotFound: "MILESTONE_NOT_FOUND"
        case .duplicateMilestoneName: "DUPLICATE_MILESTONE_NAME"
        case .milestoneProjectMismatch: "MILESTONE_PROJECT_MISMATCH"
        }
    }

    var hint: String {
        switch self {
        case .taskNotFound(let hint),
             .projectNotFound(let hint),
             .ambiguousProject(let hint),
             .invalidStatus(let hint),
             .invalidType(let hint),
             .invalidInput(let hint),
             .milestoneNotFound(let hint),
             .duplicateMilestoneName(let hint),
             .milestoneProjectMismatch(let hint):
            hint
        }
    }

    /// JSON-encoded error response using JSONSerialization for safe character escaping [req 19.1]
    var json: String {
        let dict: [String: String] = ["error": code, "hint": hint]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"\(code)\",\"hint\":\"Internal encoding error\"}"
        }
        return str
    }
}
