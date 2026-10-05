#if os(macOS)
import Foundation

nonisolated struct TaskLinkQueryOptions: Sendable {
    static let keys: Set<String> = ["hasLinks", "linkType", "linkDirection", "linkTargetTaskId", "unblocked"]
    let hasLinks: Bool?
    let type: TaskLinkType?
    let direction: String?
    let target: UUID?
    let unblocked: Bool?

    @MainActor static func parse(_ args: [String: Any]) throws -> Self? {
        guard !keys.isDisjoint(with: args.keys) else { return nil }
        func boolean(_ key: String) throws -> Bool? {
            guard let raw = args[key] else { return nil }
            guard let value = IntentHelpers.parseBoolValue(raw) else {
                throw MCPTaskQueryError.invalid("\(key) must be a boolean")
            }
            return value
        }
        let type: TaskLinkType?
        if let raw = args["linkType"] {
            guard let name = raw as? String, let parsed = TaskLinkType(rawValue: name) else {
                throw MCPTaskQueryError.invalid("linkType must be a documented public link type")
            }
            type = parsed
        } else { type = nil }
        let direction: String?
        if let raw = args["linkDirection"] {
            guard let value = raw as? String, ["incoming", "outgoing"].contains(value),
                  type == .introducedBy || type == .duplicateOf else {
                throw MCPTaskQueryError.invalid("linkDirection requires introduced-by or duplicate-of")
            }
            direction = value
        } else { direction = nil }
        let target: UUID?
        if let raw = args["linkTargetTaskId"] {
            guard type != nil, let value = raw as? String, let id = UUID(uuidString: value) else {
                throw MCPTaskQueryError.invalid("linkTargetTaskId requires a linkType and valid UUID")
            }
            target = id
        } else { target = nil }
        return try Self(hasLinks: boolean("hasLinks"), type: type, direction: direction,
                        target: target, unblocked: boolean("unblocked"))
    }

    // Each public orientation is checked against raw stored incidence.
    // swiftlint:disable:next cyclomatic_complexity
    @MainActor func matches(_ id: UUID, graph: TaskLinkGraphView?, budget: TaskLinkGraphBudget) throws -> Bool {
        try budget.check()
        guard let graph else { throw MCPReadCaptureError.incoherentCapture }
        let rows = graph.incidence[id, default: []]
        if let hasLinks, hasLinks != !rows.isEmpty { return false }
        if let unblocked {
            let assessment = graph.assessment(for: id)
            guard assessment == (unblocked ? .unblocked : .blocked) else { return false }
        }
        guard let type else { return true }
        for row in rows {
            try budget.check()
            guard !graph.invalidOccurrences.contains(row.physicalKey) else { continue }
            let incoming = row.target == id
            let opposite = incoming ? row.source : row.target
            if let target, target != opposite { continue }
            switch type {
            case .blocks: if row.kind == "dependency" && !incoming { return true }
            case .blockedBy: if row.kind == "dependency" && incoming { return true }
            case .relatesTo: if row.kind == "association" { return true }
            case .introducedBy, .duplicateOf:
                let expected = type == .introducedBy ? "attribution" : "duplicate"
                if row.kind == expected && incoming == (direction == "incoming") { return true }
            }
        }
        return false
    }
}
#endif
