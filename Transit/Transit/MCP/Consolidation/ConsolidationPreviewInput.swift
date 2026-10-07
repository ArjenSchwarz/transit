#if os(macOS)
import Foundation

nonisolated enum ConsolidationPreviewInput {
    static func apply(_ arguments: [String: Any]) throws -> (ConsolidationRequest, MCPReadPolicy) {
        try closed(arguments, allowed: ["survivorTaskId", "candidateTaskIds", "reason", "preservation",
                                        "survivorEdits", "readPolicy"])
        let survivor = try uuid(arguments["survivorTaskId"])
        guard let rawIds = arguments["candidateTaskIds"] as? [String], (1...5).contains(rawIds.count),
              let reason = arguments["reason"] as? String, nonblank(reason) else { throw invalid() }
        let candidates = try rawIds.map { try uuid($0) }
        guard Set(candidates).count == candidates.count, !candidates.contains(survivor),
              let accounting = arguments["preservation"] as? [String: Any],
              accounting.count == candidates.count else { throw invalid() }
        let edits = try edits(arguments["survivorEdits"])
        var preservation: [String: ConsolidationDisposition] = [:]
        for (key, raw) in accounting {
            let id = try uuid(key)
            guard candidates.contains(id), preservation[id.uuidString] == nil,
                  let entry = raw as? [String: Any] else { throw invalid() }
            preservation[id.uuidString] = try disposition(entry, edits: edits)
        }
        let request = ConsolidationRequest(survivorTaskId: survivor, candidateTaskIds: candidates,
            reason: reason, preservation: preservation, survivorEdits: edits)
        return (request, try policy(arguments))
    }

    static func undo(_ arguments: [String: Any]) throws -> (UUID, MCPReadPolicy) {
        try closed(arguments, allowed: ["operationId", "readPolicy"])
        return (try uuid(arguments["operationId"]), try policy(arguments))
    }

    private static func edits(_ raw: Any?) throws -> ConsolidationEdits {
        guard let raw else { return ConsolidationEdits() }
        guard let object = raw as? [String: Any] else { throw invalid() }
        try closed(object, allowed: ["description", "metadata"])
        var result = ConsolidationEdits()
        if let description = object["description"] {
            result.description = try descriptionEdit(description)
        }
        if let metadata = object["metadata"] {
            guard let strings = metadata as? [String: String] else { throw invalid() }
            result.metadata = strings
        }
        return result
    }

    private static func disposition(_ object: [String: Any], edits: ConsolidationEdits) throws
        -> ConsolidationDisposition {
        try closed(object, allowed: ["incorporated", "retainedExplanation"])
        var result = ConsolidationDisposition()
        if let raw = object["retainedExplanation"] {
            guard let text = raw as? String, nonblank(text) else { throw invalid() }
            result.retainedExplanation = text
        }
        if let raw = object["incorporated"] {
            result.incorporated = try incorporated(raw, edits: edits)
        }
        guard !result.incorporated.isEmpty || result.retainedExplanation != nil else { throw invalid() }
        return result
    }

    private static func descriptionEdit(_ raw: Any) throws -> ConsolidationDescriptionEdit {
        if raw is NSNull { return .replace(nil) }
        guard let text = raw as? String else { throw invalid() }
        return .replace(text)
    }

    private static func incorporated(_ raw: Any, edits: ConsolidationEdits) throws
        -> [ConsolidationDisposition.Reference] {
        guard let references = raw as? [[String: String]], !references.isEmpty else { throw invalid() }
        return try references.map { reference in
            guard Set(reference.keys) == ["sourceDetail", "survivorField"],
                  let source = reference["sourceDetail"], nonblank(source),
                  let field = reference["survivorField"] else { throw invalid() }
            switch field {
            case "description": guard case .replace = edits.description else { throw invalid() }
            case "metadata": guard edits.metadata != nil else { throw invalid() }
            default: throw invalid()
            }
            return .init(sourceDetail: source, survivorField: field)
        }
    }

    private static func closed(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else { throw invalid() }
    }

    private static func uuid(_ raw: Any?) throws -> UUID {
        guard let text = raw as? String, let id = UUID(uuidString: text) else { throw invalid() }
        return id
    }

    private static func policy(_ object: [String: Any]) throws -> MCPReadPolicy {
        guard let value = MCPReadRefreshPolicy.parse(object["readPolicy"]) else { throw invalid() }
        return value
    }

    private static func nonblank(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func invalid() -> MCPTaskQueryError {
        MCPTaskQueryError.invalid("Invalid complete consolidation preview input")
    }
}
#endif
