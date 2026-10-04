#if os(macOS)
import Foundation

nonisolated enum MCPSnapshotTaskQueryError: Error, Equatable, Sendable {
    case invalidInput
    case incompatible
    case invalidCursor
}

nonisolated enum MCPSnapshotTaskQueryRequest: Sendable {
    case initial(snapshotId: String, detail: SnapshotTaskDetail, limit: Int, projectId: UUID?, statuses: [String])
    case continuation(cursor: String, policy: MCPReadPolicy?)

    static let supportedStatuses = [
        "idea", "planning", "spec", "ready-for-implementation", "in-progress",
        "ready-for-review", "done", "abandoned"
    ]

    @MainActor static func parse(_ arguments: [String: Any]) throws -> Self {
        if let raw = arguments["cursor"] { return try continuation(arguments, raw: raw) }
        guard Set(arguments.keys).isSubset(of: [
            "snapshotId", "detailLevel", "includeComments", "limit", "projectId", "status"
        ]) else { throw MCPSnapshotTaskQueryError.incompatible }
        guard let snapshotID = arguments["snapshotId"] as? String, UUID(uuidString: snapshotID) != nil,
              let detailString = arguments["detailLevel"] as? String,
              let detail = SnapshotTaskDetail(rawValue: detailString),
              let comments = IntentHelpers.parseBoolValue(arguments["includeComments"]),
              let limit = IntentHelpers.parseIntValue(arguments["limit"]), (1...100).contains(limit) else {
            throw MCPSnapshotTaskQueryError.invalidInput
        }
        guard !comments else { throw MCPSnapshotTaskQueryError.incompatible }
        let projectID: UUID?
        if let raw = arguments["projectId"] {
            guard let string = raw as? String, let id = UUID(uuidString: string) else {
                throw MCPSnapshotTaskQueryError.invalidInput
            }
            projectID = id
        } else { projectID = nil }
        let statuses: [String]
        if let raw = arguments["status"] {
            guard let array = raw as? [String], array.allSatisfy({ supportedStatuses.contains($0) }) else {
                throw MCPSnapshotTaskQueryError.invalidInput
            }
            let selected = Set(array)
            statuses = supportedStatuses.filter { selected.contains($0) }
        } else { statuses = [] }
        return .initial(snapshotId: snapshotID, detail: detail, limit: limit, projectId: projectID, statuses: statuses)
    }
    @MainActor private static func continuation(_ arguments: [String: Any], raw: Any) throws -> Self {
        guard Set(arguments.keys).isSubset(of: ["cursor", "readPolicy"]) else {
            throw MCPSnapshotTaskQueryError.incompatible
        }
        guard let policy = MCPReadRefreshPolicy.parse(arguments["readPolicy"]) else {
            throw MCPSnapshotTaskQueryError.invalidInput
        }
        guard let cursor = raw as? String, MCPCursorFamily.classify(cursor) == .reusable else {
            throw MCPSnapshotTaskQueryError.invalidCursor
        }
        return .continuation(cursor: cursor, policy: arguments["readPolicy"] == nil ? nil : policy)
    }

}
#endif
