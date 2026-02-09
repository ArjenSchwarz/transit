import Foundation

/// Shared utilities for App Intent JSON parsing and response encoding.
/// Nonisolated because these are pure functions that only use Foundation types.
nonisolated enum IntentHelpers {

    /// Parses a JSON string into a dictionary. Returns nil for malformed input.
    static func parseJSON(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Encodes a dictionary as a JSON string. Returns an error JSON on failure.
    static func encodeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return IntentError.invalidInput(hint: "Failed to encode response").json
        }
        return string
    }

    /// Encodes an array of dictionaries as a JSON string.
    static func encodeJSONArray(_ array: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Translates ProjectLookupError to IntentError.
    static func mapProjectLookupError(_ error: ProjectLookupError) -> IntentError {
        switch error {
        case .notFound(let hint):
            .projectNotFound(hint: hint)
        case .ambiguous(let hint):
            .ambiguousProject(hint: hint)
        case .noIdentifier:
            .invalidInput(hint: "Either projectId or project name is required")
        }
    }
}
