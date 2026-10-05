#if os(macOS)
import Foundation

/// Shape validation has no store access. Semantic references and exact selector
/// evidence remain domain validation after durable replay and acceptance.
@MainActor struct TaskLinkWireRequest {
    static let fields: Set<String> = ["linkChanges", "endpointPreconditions"]
    let changes: [TaskLinkChange]
    let endpointPreconditions: [UUID: String]

    static func parse(tool: String, arguments: [String: Any]) throws -> Self? {
        guard arguments["linkChanges"] != nil || arguments["endpointPreconditions"] != nil else { return nil }
        guard ["create_task", "update_task"].contains(tool) else { throw invalid() }
        let raw = try objects(arguments["linkChanges"])
        let source = (arguments["taskId"] as? String).flatMap(UUID.init(uuidString:))
        var changes: [TaskLinkChange] = []
        var removals: Set<UUID> = []
        var additions: Set<String> = []
        for fields in raw {
            let change = try directive(fields, creating: tool == "create_task", source: source)
            switch change {
            case let .add(type, target):
                guard additions.insert(type.rawValue + ":" + target.uuidString).inserted else { throw invalid() }
            case let .remove(id, _):
                guard removals.insert(id).inserted else { throw invalid() }
            }
            changes.append(change)
        }
        var guards: [UUID: String] = [:]
        for fields in try objects(arguments["endpointPreconditions"]) {
            guard Set(fields.keys) == ["taskId", "expectedRevision"],
                  let id = uuid(fields["taskId"]), id != source,
                  let revision = fields["expectedRevision"] as? String, token(revision, prefix: "r1"),
                  guards.updateValue(revision, forKey: id) == nil else { throw invalid() }
        }
        return Self(changes: changes, endpointPreconditions: guards)
    }

    private static func directive(_ fields: [String: Any], creating: Bool, source: UUID?) throws -> TaskLinkChange {
        switch fields["action"] as? String {
        case "add":
            guard Set(fields.keys) == ["action", "type", "targetTaskId"],
                  let rawType = fields["type"] as? String, let type = TaskLinkType(rawValue: rawType),
                  let target = uuid(fields["targetTaskId"]), target != source else { throw invalid() }
            return .add(type: type, target: target)
        case "remove":
            guard !creating, Set(fields.keys) == ["action", "edgeId", "occurrenceRevision"],
                  let edge = uuid(fields["edgeId"]), let revision = fields["occurrenceRevision"] as? String,
                  token(revision, prefix: "l1") else { throw invalid() }
            return .remove(edgeId: edge, occurrenceRevision: revision)
        default: throw invalid()
        }
    }

    private static func objects(_ value: Any?) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let objects = value as? [[String: Any]], objects.count <= 50 else { throw invalid() }
        return objects
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func token(_ value: String, prefix: String) -> Bool {
        let pattern = "^" + prefix + ":[0-9a-f]{64}$"
        return value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }

    private static func invalid() -> MCPWriteFailure {
        MCPWriteFailure("INVALID_INPUT", "Invalid typed-link directive or endpoint precondition")
    }
}
#endif
