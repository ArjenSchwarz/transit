#if os(macOS)
import Foundation

/// Positions are explicit public shapes; no recursive search through unknown data.
nonisolated enum MCPResultLinks {
    static func build(_ source: MCPResultSource, context: MCPResultContext,
                      checkpoint: @Sendable () throws -> Void) throws -> [MCPUnavailableLink] {
        guard let document = source.document else { return [] }
        var positions = try builtins(tool: context.tool, value: document.value, checkpoint: checkpoint)
        positions.append(contentsOf: context.entityPositions)
        var candidates: [MCPResultLinkCandidate] = []
        var seen: Set<MCPResultLinkKey> = []
        for (index, position) in positions.enumerated() {
            if index.isMultiple(of: 64) { try checkpoint() }
            guard let match = try MCPResultInspection.pointer(position.sourcePath, in: document.value,
                                                              checkpoint: checkpoint),
                  let identity = try identity(match.value, type: position.entityType, checkpoint: checkpoint) else {
                continue
            }
            let key = MCPResultLinkKey(path: Array(position.sourcePath.utf8),
                                      type: position.entityType.rawValue, identity: identity)
            guard seen.insert(key).inserted else { continue }
            let link = MCPUnavailableLink(entityType: position.entityType, entityId: identity,
                                          sourcePath: position.sourcePath)
            candidates.append(MCPResultLinkCandidate(link: link, order: match.order))
        }
        try checkpoint()
        var comparisons = 0
        try candidates.sort { left, right in
            if comparisons.isMultiple(of: 64) { try checkpoint() }
            comparisons += 1
            return precedes(left, right)
        }
        try checkpoint()
        return candidates.map(\.link)
    }

    private static func identity(_ value: MCPJSONValue, type: MCPResultEntityType,
                                 checkpoint: @Sendable () throws -> Void) throws -> UUID? {
        let token: String?
        if case .string(let direct) = value {
            token = direct
        } else {
            let field = type == .task ? "taskId" : "projectId"
            token = MCPResultInspection.string(try MCPResultInspection.member(field, in: value, checkpoint: checkpoint))
        }
        return token.flatMap(UUID.init(uuidString:))
    }

    private static func builtins(tool: String, value: MCPJSONValue,
                                 checkpoint: @Sendable () throws -> Void) throws -> [MCPResultEntityPosition] {
        switch tool {
        case "query_tasks": return try taskQueryPositions(value, checkpoint: checkpoint)
        case "get_projects":
            return try projectArrayPositions(value, suffix: "", checkpoint: checkpoint)
        case "query_milestones":
            return try projectArrayPositions(value, suffix: "/projectId", checkpoint: checkpoint)
        case "create_task", "update_task", "update_task_status":
            return ["/record", "/currentRecord", "/recordBeforeDeletion"].flatMap(taskPositions)
        case "create_project":
            return ["/record", "/currentRecord", "/recordBeforeDeletion"].map {
                .init(entityType: .project, sourcePath: $0)
            }
        case "add_comment": return [.init(entityType: .task, sourcePath: "/record/taskId")]
        case "create_milestone", "update_milestone", "delete_milestone":
            return ["/record", "/currentRecord", "/recordBeforeDeletion"].map {
                .init(entityType: .project, sourcePath: $0 + "/projectId")
            }
        default: return []
        }
    }

    private static func projectArrayPositions(_ value: MCPJSONValue, suffix: String,
                                              checkpoint: @Sendable () throws -> Void) throws
        -> [MCPResultEntityPosition] {
        guard case .array(let records) = value else { return [] }
        var positions: [MCPResultEntityPosition] = []
        for index in records.indices {
            // Check before allocating the next chunk of positions, including the first.
            if index.isMultiple(of: 64) { try checkpoint() }
            positions.append(.init(entityType: .project, sourcePath: "/\(index)" + suffix))
        }
        return positions
    }

    private static func taskQueryPositions(_ value: MCPJSONValue,
                                           checkpoint: @Sendable () throws -> Void) throws
        -> [MCPResultEntityPosition] {
        let records: [MCPJSONValue]
        let prefix: String
        if case .array(let rootRecords) = value {
            records = rootRecords
            prefix = ""
        } else if case .array(let pageRecords) = try MCPResultInspection.member("results", in: value,
                                                                               checkpoint: checkpoint) {
            records = pageRecords
            prefix = "/results"
        } else { return [] }
        var positions: [MCPResultEntityPosition] = []
        for (index, record) in records.enumerated() {
            if index.isMultiple(of: 64) { try checkpoint() }
            let path = prefix + "/\(index)"
            let task = try MCPResultInspection.member("task", in: record, checkpoint: checkpoint)
            let requested = try MCPResultInspection.member("requested", in: record, checkpoint: checkpoint)
            if task != nil {
                positions.append(contentsOf: taskPositions(path + "/task"))
            } else if requested == nil {
                positions.append(contentsOf: taskPositions(path))
            }
        }
        return positions
    }

    private static func taskPositions(_ path: String) -> [MCPResultEntityPosition] {
        [.init(entityType: .task, sourcePath: path), .init(entityType: .project, sourcePath: path + "/projectId")]
    }

    private static func precedes(_ lhs: MCPResultLinkCandidate, _ rhs: MCPResultLinkCandidate) -> Bool {
        for (left, right) in zip(lhs.order, rhs.order) where left != right {
            switch (left, right) {
            case (.member(let first), .member(let second)): return first.lexicographicallyPrecedes(second)
            case (.element(let first), .element(let second)): return first < second
            case (.member, .element): return true
            case (.element, .member): return false
            }
        }
        if lhs.order.count != rhs.order.count { return lhs.order.count < rhs.order.count }
        if lhs.link.entityType != rhs.link.entityType {
            return lhs.link.entityType.rawValue < rhs.link.entityType.rawValue
        }
        return lhs.link.entityId.uuidString < rhs.link.entityId.uuidString
    }
}

nonisolated private struct MCPResultLinkCandidate {
    let link: MCPUnavailableLink
    let order: [MCPResultPointerOrder]
}

nonisolated private struct MCPResultLinkKey: Hashable {
    let path: [UInt8]
    let type: String
    let identity: UUID
}
#endif
