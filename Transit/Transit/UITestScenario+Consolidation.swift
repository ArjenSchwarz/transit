import Foundation
import SwiftData
extension UITestScenario {
    /// Synthetic immutable evidence only; the UI-test container disables CloudKit and live MCP.
    @MainActor func seedConsolidationHistory(into context: ModelContext) {
        do {
            let project = Project(name: "Consolidation", description: "Synthetic history fixture",
                gitRepo: nil, colorHex: "#0A84FF")
            let survivor = TransitTask(name: "History Survivor", type: .feature, project: project,
                displayID: .permanent(1))
            let candidate = TransitTask(name: "History Original", description: "Retained detail", type: .feature,
                project: project, displayID: .permanent(2))
            survivor.statusRawValue = TaskStatus.inProgress.rawValue
            survivor.id = UUID(uuidString: "00000000-0000-0000-0000-000000238101")!
            candidate.id = UUID(uuidString: "00000000-0000-0000-0000-000000238102")!
            let instant = Date(timeIntervalSinceReferenceDate: 123)
            let prior = TaskConsolidationRawFields(description: candidate.taskDescription, metadataJSON: nil,
                statusRawValue: "idea", lastStatusChangeDate: try TaskConsolidationRawFields.exactDate(instant),
                completionDate: nil)
            candidate.statusRawValue = "abandoned"
            candidate.lastStatusChangeDate = instant
            candidate.completionDate = instant
            let after = try TaskConsolidationRawFields.capture(candidate)
            let edge = TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate", sourceTaskID: candidate.id,
                targetTaskID: survivor.id, createdAt: instant)
            context.insert(project)
            context.insert(survivor)
            context.insert(candidate)
            context.insert(edge)
            let operation = UUID(uuidString: "00000000-0000-0000-0000-000000238100")!
            let value = TaskLinkOccurrenceValue(physicalKey: Data([1]), id: edge.id, kind: "duplicate",
                source: candidate.id, target: survivor.id, createdAt: instant)
            let created = TaskConsolidationOccurrence(id: edge.id, kind: "duplicate", source: candidate.id,
                target: survivor.id, createdAt: try TaskConsolidationRawFields.exactDate(instant),
                revision: try TaskLinkGraph.occurrenceRevision(value))
            try context.save()
            let graph = try TaskLinkService.graph(in: context, evaluationInstant: instant)
            let revisions = try [survivor, candidate].map { task in
                (task.id.uuidString, try MCPRecordSnapshot.task(task,
                    incidence: graph.occurrences) { _ in [] }.revision)
            }
            let preservation = try consolidationPreservation(candidate.id)
            let payload = TaskConsolidationPayload(operationId: operation, kind: "apply", survivorTaskId: survivor.id,
                candidateTaskIds: [candidate.id], reason: "Synthetic reviewed history",
                    preservationJSON: preservation, changes: [.init(taskId: candidate.id, before: prior, after: after)],
                appliedRevisions: Dictionary(uniqueKeysWithValues: revisions), createdOccurrences: [created],
                retainedOccurrences: [], requestKey: "ui-fixture", reviewId: UUID(),
                reviewRevision: "p1:" + String(repeating: "a", count: 64),
                mappings: try TaskConsolidationMapping.capture([survivor.id, candidate.id], graph: graph,
                    budget: TaskLinkGraphBudget()))
            context.insert(TaskConsolidationEvent(id: operation, operationId: operation, kindRawValue: "apply",
                createdAt: instant, originScopeId: "ui-test-fixture", survivorTaskId: survivor.id,
                candidateTaskIds: [candidate.id], payloadJSON: try TaskConsolidationHistoryCodec.encode(payload)))
            try context.save()
        } catch { preconditionFailure("Could not save synthetic consolidation history fixture: \(error)") }
    }

    private func consolidationPreservation(_ id: UUID) throws -> String {
        let accounting = try JSONSerialization.data(withJSONObject: [id.uuidString:
            ["retainedExplanation": "Original description remains available"]], options: [.sortedKeys])
        guard let preservation = String(data: accounting, encoding: .utf8) else {
            throw TaskConsolidationHistoryError.malformed
        }
        return preservation
    }
}
