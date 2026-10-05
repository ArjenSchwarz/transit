#if os(macOS)
import Foundation

/// Observation-only enrichment from the same frozen graph as the task record.
@MainActor enum TaskLinkQueryProjection {
    static func detail(_ id: UUID, graph: TaskLinkGraphView?, budget: TaskLinkGraphBudget) throws -> [String: Any] {
        try budget.check()
        guard let graph else {
            return ["graphCoverage": "unavailable", "links": NSNull(), "linkDiagnostics": NSNull(),
                "duplicateResolution": NSNull(), "blockerAssessment": ["assessment": "unavailable"]]
        }
        var links: [[String: Any]] = []
        for row in graph.incidence[id, default: []] {
            try budget.check()
            let incoming = row.target == id
            let opposite = incoming ? row.source : row.target
            let matches = graph.tasksById[opposite, default: []]
            let name: Any = matches.count == 1 ? matches[0].name : NSNull()
            let type: String
            switch row.kind {
            case "dependency": type = incoming ? "blocked-by" : "blocks"
            case "association": type = "relates-to"
            case "attribution": type = "introduced-by"
            case "duplicate": type = "duplicate-of"
            default: type = row.kind
            }
            var value: [String: Any] = ["edgeId": row.id.uuidString, "storedKind": row.kind, "type": type,
                "sourceTaskId": row.source.uuidString, "targetTaskId": row.target.uuidString,
                "oppositeTaskId": opposite.uuidString, "targetName": name,
                "direction": incoming ? "incoming" : "outgoing",
                "physicalIdentity": row.physicalKey.base64EncodedString(),
                "valid": !graph.invalidOccurrences.contains(row.physicalKey)]
            if graph.occurrencesById[row.id]?.count == 1,
               let revision = try? TaskLinkGraph.occurrenceRevision(row) { value["occurrenceRevision"] = revision }
            links.append(value)
        }
        let incidentIDs = Set(graph.incidence[id, default: []].map(\.id))
        var diagnostics: [[String: Any]] = []
        for diagnostic in graph.diagnostics {
            try budget.check()
            guard diagnostic.taskIds.contains(id) || diagnostic.edgeId.map(incidentIDs.contains) == true
            else { continue }
            var value: [String: Any] = ["code": diagnostic.code,
                "taskIds": diagnostic.taskIds.map(\.uuidString),
                "physicalIdentity": diagnostic.physicalKey.base64EncodedString()]
            value["edgeId"] = diagnostic.edgeId?.uuidString
            diagnostics.append(value)
        }
        let duplicate = try TaskLinkGraph.duplicateResolution(for: id, in: graph, budget: budget)
        let result: [String: Any] = ["graphCoverage": "available", "links": links, "linkDiagnostics": diagnostics,
            "duplicateResolution": ["path": duplicate.path.map(\.uuidString),
                "canonicalTaskId": duplicate.canonical?.uuidString as Any? ?? NSNull(),
                "diagnostic": duplicate.diagnostic as Any? ?? NSNull()],
            "blockerAssessment": ["assessment": graph.assessment(for: id).rawValue,
                                  "evaluatedAt": MCPRecordSnapshot.timestamp(graph.evaluationInstant)]]
        try budget.check(); return result
    }
}
#endif
