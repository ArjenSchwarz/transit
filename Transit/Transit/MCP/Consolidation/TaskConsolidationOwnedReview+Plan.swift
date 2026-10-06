#if os(macOS)
import Foundation
extension TaskConsolidationOwnedReview {
    static func make(plan: ConsolidationPlan, scope: String, id: UUID = UUID(),
                     revision: String? = nil) throws -> Self {
        let revision = revision ?? plan.reviewRevision
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let accounting = String(data: try encoder.encode(plan.request.preservation), encoding: .utf8) else {
            throw ConsolidationPlanningError.invalidInput
        }
        let revisions = Dictionary(uniqueKeysWithValues: plan.originals.map { ($0.id, $0.revision) })
        let payload = TaskConsolidationPayload(operationId: UUID(), kind: "apply",
            survivorTaskId: plan.request.survivorTaskId, candidateTaskIds: plan.request.candidateTaskIds,
            reason: plan.request.reason, preservationJSON: accounting, changes: plan.changes.map(\.delta),
            appliedRevisions: Dictionary(uniqueKeysWithValues: revisions.map { ($0.key.uuidString, $0.value) }),
            createdOccurrences: [], retainedOccurrences: plan.retainedOccurrences, requestKey: "preview",
            reviewId: id, reviewRevision: revision)
        return Self(id: id, revision: revision, originScopeId: scope, payload: payload,
            changes: plan.changes, expectedRevisions: revisions, links: plan.links)
    }
}
#endif
