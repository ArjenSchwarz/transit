#if os(macOS)
import Foundation

struct MCPTaskQueryError: Error {
    let code: String
    let message: String

    static func invalid(_ message: String) -> Self { Self(code: "INVALID_INPUT", message: message) }
}

struct MCPTaskQueryRequest {
    enum Selector {
        case list
        case single(Int)
        case taskIDs([String])
        case displayIDs([Int])
    }

    let cursor: String?
    let detailLevel: String
    let includeComments: Bool
    let limit: Int
    let selector: Selector

    static let filterKeys: Set<String> = [
        "project", "projectId", "status", "not_status", "unfinished", "type", "priority",
        "milestone", "milestoneDisplayId", "search"
    ]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func parse(_ args: [String: Any]) throws -> Self {
        if let raw = args["cursor"] {
            guard args.count == 1 else {
                throw MCPTaskQueryError.invalid("Continuation requires only a cursor")
            }
            guard let cursor = raw as? String, UUID(uuidString: cursor) != nil else {
                throw MCPTaskQueryError(code: "INVALID_CURSOR", message: "Invalid cursor; start a new query")
            }
            return Self(cursor: cursor, detailLevel: "summary", includeComments: false, limit: 1, selector: .list)
        }
        let allowed = filterKeys.union([
            "detailLevel", "includeComments", "limit", "displayId", "taskIds", "displayIds"
        ])
        guard Set(args.keys).isSubset(of: allowed) else {
            throw MCPTaskQueryError.invalid("Unknown query field")
        }
        guard let detail = args["detailLevel"] as? String, ["summary", "full"].contains(detail) else {
            throw MCPTaskQueryError.invalid("detailLevel is required and must be summary or full")
        }
        guard let comments = IntentHelpers.parseBoolValue(args["includeComments"]) else {
            throw MCPTaskQueryError.invalid("includeComments is required and must be a boolean")
        }
        guard let limit = IntentHelpers.parseIntValue(args["limit"]), (1...100).contains(limit) else {
            throw MCPTaskQueryError.invalid("limit is required and must be an integer from 1 through 100")
        }
        let selectors = ["displayId", "taskIds", "displayIds"].filter { args[$0] != nil }
        guard selectors.count <= 1 else { throw MCPTaskQueryError.invalid("Use only one task selector") }
        if args["taskIds"] != nil || args["displayIds"] != nil {
            guard filterKeys.isDisjoint(with: args.keys) else {
                throw MCPTaskQueryError.invalid("Batch selectors cannot be combined with filters")
            }
        }
        let selector: Selector
        if let raw = args["displayId"] {
            guard let value = IntentHelpers.parseIntValue(raw) else {
                throw MCPTaskQueryError.invalid("displayId must be an integer")
            }
            selector = .single(value)
        } else if let raw = args["taskIds"] {
            let values = try batch(raw, key: "taskIds")
            guard let ids = values as? [String], ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
                throw MCPTaskQueryError.invalid("taskIds must contain valid UUID strings")
            }
            selector = .taskIDs(ids)
        } else if let raw = args["displayIds"] {
            let values = try batch(raw, key: "displayIds")
            let ids = values.compactMap { IntentHelpers.parseIntValue($0) }
            guard ids.count == values.count else {
                throw MCPTaskQueryError.invalid("displayIds must contain integers")
            }
            selector = .displayIDs(ids)
        } else {
            selector = .list
        }
        return Self(cursor: nil, detailLevel: detail, includeComments: comments, limit: limit, selector: selector)
    }

    private static func batch(_ raw: Any, key: String) throws -> [Any] {
        guard let values = raw as? [Any], (1...100).contains(values.count) else {
            throw MCPTaskQueryError.invalid("\(key) must contain 1 through 100 identifiers")
        }
        return values
    }
}
#endif
