import Foundation

/// Structured error codes for App Intent failures.
/// All errors encode to JSON format: {"error": "<CODE>", "hint": "<message>"}
enum IntentError: Error {
    case taskNotFound(hint: String)
    case projectNotFound(hint: String)
    case ambiguousProject(hint: String)
    case invalidStatus(hint: String)
    case invalidType(hint: String)
    case invalidInput(hint: String)

    var code: String {
        switch self {
        case .taskNotFound: return "TASK_NOT_FOUND"
        case .projectNotFound: return "PROJECT_NOT_FOUND"
        case .ambiguousProject: return "AMBIGUOUS_PROJECT"
        case .invalidStatus: return "INVALID_STATUS"
        case .invalidType: return "INVALID_TYPE"
        case .invalidInput: return "INVALID_INPUT"
        }
    }

    var hint: String {
        switch self {
        case .taskNotFound(let hint),
             .projectNotFound(let hint),
             .ambiguousProject(let hint),
             .invalidStatus(let hint),
             .invalidType(let hint),
             .invalidInput(let hint):
            return hint
        }
    }

    /// JSON-encoded error response. Uses JSONSerialization to safely escape
    /// special characters in the hint string.
    var json: String {
        let dict: [String: String] = ["error": code, "hint": hint]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"\(code)\",\"hint\":\"Internal encoding error\"}"
        }
        return str
    }
}
