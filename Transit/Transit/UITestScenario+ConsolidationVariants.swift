import Foundation
import SwiftData

extension UITestScenario {
    @MainActor func varyConsolidationHistory(_ payload: TaskConsolidationPayload, candidate: TransitTask,
                                             edge: TaskLinkOccurrence, context: ModelContext) throws {
        switch self {
        case .consolidationHistoryMissing: context.delete(candidate)
        case .consolidationHistoryAmbiguous:
            guard let project = candidate.project else { throw TaskConsolidationHistoryError.malformed }
            let duplicate = TransitTask(name: "Ambiguous history original", type: .feature,
                project: project, displayID: .permanent(3))
            duplicate.id = candidate.id
            context.insert(duplicate)
        case .consolidationHistoryOverLimit:
            candidate.taskDescription = String(repeating: "x", count: 17 * 1_024 * 1_024)
        case .consolidationHistoryUnavailable:
            context.insert(try TaskConsolidationEvent(id: UUID(), operationId: payload.operationId,
                kindRawValue: "undo", createdAt: Date(timeIntervalSinceReferenceDate: 124),
                originScopeId: "ui-test-fixture", survivorTaskId: payload.survivorTaskId,
                candidateTaskIds: payload.candidateTaskIds, payloadJSON: "malformed imported history"))
        case .consolidationHistoryReversed:
            candidate.statusRawValue = "idea"
            candidate.completionDate = nil
            context.delete(edge)
            let inverse = TaskConsolidationPayload(operationId: payload.operationId, kind: "undo",
                survivorTaskId: payload.survivorTaskId, candidateTaskIds: payload.candidateTaskIds,
                reason: payload.reason, preservationJSON: payload.preservationJSON,
                changes: payload.changes.map(\.inverse), appliedRevisions: payload.appliedRevisions,
                createdOccurrences: [], retainedOccurrences: payload.retainedOccurrences,
                removedOccurrences: payload.createdOccurrences, requestKey: "ui-reversal", reviewId: UUID(),
                reviewRevision: payload.reviewRevision, mappings: payload.mappings)
            context.insert(try TaskConsolidationEvent(id: UUID(), operationId: payload.operationId,
                kindRawValue: "undo", createdAt: Date(timeIntervalSinceReferenceDate: 124),
                originScopeId: "ui-test-fixture", survivorTaskId: payload.survivorTaskId,
                candidateTaskIds: payload.candidateTaskIds,
                payloadJSON: try TaskConsolidationHistoryCodec.encode(inverse)))
        default: return
        }
        try context.save()
    }
}
