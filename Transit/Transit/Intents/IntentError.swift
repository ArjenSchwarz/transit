import Foundation

enum IntentError: Swift.Error, Equatable {
    case invalidInput(hint: String)
    case invalidType(hint: String)
    case projectNotFound(hint: String)
    case ambiguousProject(hint: String)
    case taskNotFound(hint: String)
    case invalidStatus(hint: String)

    nonisolated var code: String {
        switch self {
        case .invalidInput:
            return "INVALID_INPUT"
        case .invalidType:
            return "INVALID_TYPE"
        case .projectNotFound:
            return "PROJECT_NOT_FOUND"
        case .ambiguousProject:
            return "AMBIGUOUS_PROJECT"
        case .taskNotFound:
            return "TASK_NOT_FOUND"
        case .invalidStatus:
            return "INVALID_STATUS"
        }
    }

    nonisolated var hint: String {
        switch self {
        case .invalidInput(let hint),
             .invalidType(let hint),
             .projectNotFound(let hint),
             .ambiguousProject(let hint),
             .taskNotFound(let hint),
             .invalidStatus(let hint):
            return hint
        }
    }

    nonisolated var response: String {
        let payload: [String: Any] = [
            "ok": false,
            "error": [
                "code": code,
                "hint": hint
            ]
        ]
        return IntentJSON.encode(payload)
    }
}

enum IntentJSON {
    nonisolated static func encode(_ payload: Any) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"error":{"code":"INVALID_INPUT","hint":"Unable to encode JSON response."},"ok":false}"#
        }
        return json
    }

    nonisolated static func parseObject(from input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}
