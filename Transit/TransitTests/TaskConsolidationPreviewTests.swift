#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationPreviewTests {
    private func arguments(_ fixture: ConsolidationPlanningFixture) -> [String: Any] {
        ["survivorTaskId": fixture.request.survivorTaskId.uuidString,
         "candidateTaskIds": fixture.request.candidateTaskIds.map(\.uuidString),
         "reason": "caller reason", "preservation": fixture.request.preservation.mapValues {
             ["retainedExplanation": $0.retainedExplanation ?? ""]
         }, "survivorEdits": ["description": NSNull(), "metadata": ["new": "value"]], "readPolicy": "cached"]
    }

    @Test func strictInputsKeepNullOmissionAndOrderedNormalizedIdentity() throws {
        let fixture = try ConsolidationPlanningFixture(seed: 1, count: 2)
        let raw = arguments(fixture)
        let (request, policy) = try ConsolidationPreviewInput.apply(raw)
        #expect(request.candidateTaskIds == fixture.request.candidateTaskIds)
        #expect(request.survivorEdits.description == .replace(nil))
        #expect(request.survivorEdits.metadata == ["new": "value"] && policy == .cached)
        var omitted = raw
        omitted.removeValue(forKey: "survivorEdits")
        #expect(try ConsolidationPreviewInput.apply(omitted).0.survivorEdits.description == .omitted)
        let operation = UUID()
        #expect(try ConsolidationPreviewInput.undo(["operationId": operation.uuidString,
            "readPolicy": "cached"]).0 == operation)
    }

    @Test(arguments: ["write-key", "unknown", "number", "self", "duplicate",
                      "bad-policy", "bad-edit", "bad-accounting"])
    func malformedWholeShapeFailsBeforeCapture(fault: String) throws {
        let fixture = try ConsolidationPlanningFixture(seed: 1, count: 2)
        var raw = arguments(fixture)
        switch fault {
        case "write-key": raw["idempotencyKey"] = "forbidden-preview-key"
        case "unknown": raw["future"] = true
        case "number": raw["survivorTaskId"] = 1
        case "self": raw["candidateTaskIds"] = [fixture.request.survivorTaskId.uuidString]
        case "duplicate": raw["candidateTaskIds"] = [fixture.request.candidateTaskIds[0].uuidString,
                                                       fixture.request.candidateTaskIds[0].uuidString.lowercased()]
        case "bad-policy": raw["readPolicy"] = false
        case "bad-edit": raw["survivorEdits"] = ["name": "not editable"]
        default: raw["preservation"] = [fixture.request.candidateTaskIds[0].uuidString: ["future": "unknown"]]
        }
        #expect(throws: (any Error).self) { try ConsolidationPreviewInput.apply(raw) }
        #expect(throws: (any Error).self) {
            try ConsolidationPreviewInput.undo(["operationId": UUID().uuidString, "idempotencyKey": "forbidden"])
        }
    }

    @Test func previewContainsCompleteOriginalsAccountingAndOnlyProposedEffects() throws {
        let fixture = try TaskConsolidationCommitFixture()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
                                                   fence: .actorOnlyTestFixture)
        let ids = [fixture.base.target.id, fixture.base.source.id, fixture.extra.id]
        let evidence = try capture.capture(selectedTaskIds: ids)
        let request = ConsolidationRequest(survivorTaskId: ids[0], candidateTaskIds: Array(ids.dropFirst()),
            reason: "explicit reason", preservation: Dictionary(uniqueKeysWithValues: ids.dropFirst().map {
                ($0.uuidString, ConsolidationDisposition(retainedExplanation: "all original detail retained"))
            }))
        let before = evidence.originals
        let data = try TaskConsolidationPreviewProjection.apply(request, evidence: evidence)
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((result["originals"] as? [[String: Any]])?.count == 3)
        #expect(result["reason"] as? String == request.reason)
        #expect((result["preservation"] as? [String: Any])?.count == 2)
        #expect((result["plannedLinks"] as? [String: Any])?["createdAt"] as? String == "assigned_at_commit")
        #expect((String(bytes: data, encoding: .utf8) ?? "").contains("original comment"))
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(
            capture.capture(selectedTaskIds: ids).originals, before))
        #expect(try fixture.base.owner.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        #expect(fixture.observation.commitSaves == 0 && !fixture.base.owner.context.hasChanges)
    }

    @Test func originalsExposeDirectAndCanonicalSavedDuplicateChain() throws {
        let fixture = try ConsolidationPlanningFixture(seed: 1, count: 2)
        let ids = fixture.originals.map(\.id)
        let graph = try TaskLinkGraph.project(tasks: fixture.graph.tasks,
            occurrences: [fixture.edge(ids[1], ids[2]), fixture.edge(ids[2], ids[0])],
            removalEvidence: [], evaluationInstant: fixture.graph.evaluationInstant)
        let evidence = ConsolidationSavedEvidence(selectedTaskIds: ids, originals: fixture.originals,
            events: [], history: [], graph: graph, encodedByteCount: 0)
        let result = try #require(JSONSerialization.jsonObject(with:
            TaskConsolidationPreviewProjection.apply(fixture.request, evidence: evidence)) as? [String: Any])
        let originals = try #require(result["originals"] as? [[String: Any]])
        let candidate = try #require(originals.first { $0["taskId"] as? String == ids[1].uuidString })
        let resolution = try #require(candidate["duplicateResolution"] as? [String: Any])
        #expect(resolution["path"] as? [String] == [ids[1], ids[2], ids[0]].map(\.uuidString))
        #expect(resolution["canonicalTaskId"] as? String == ids[0].uuidString)
        let links = try #require(candidate["links"] as? [[String: Any]])
        #expect(links.contains { $0["targetTaskId"] as? String == ids[2].uuidString })
        let survivor = try #require(originals.first { $0["taskId"] as? String == ids[0].uuidString })
        #expect((survivor["duplicateResolution"] as? [String: Any])?["canonicalTaskId"] as? String
            == ids[0].uuidString)
    }

    @Test func projectionAndProposalUseOriginalExpiredPlanningBudget() async throws {
        let fixture = try ConsolidationPreviewFixture()
        let evidence = try fixture.capture()
        let request = try ConsolidationPreviewInput.apply(fixture.arguments).0
        let expired = TaskLinkGraphBudget(deadline: .now - .seconds(1))
        #expect(throws: (any Error).self) {
            try TaskConsolidationPreviewProjection.apply(request, evidence: evidence, budget: expired)
        }
        #expect(throws: (any Error).self) {
            try ConsolidationReviewProposal(request: request, operationId: nil, evidence: evidence, budget: expired)
        }
        _ = await fixture.base.execute()
        let applied = try fixture.capture()
        let operation = try #require(applied.events.first?.operationId)
        #expect(throws: (any Error).self) {
            try TaskConsolidationPreviewProjection.undo(operation, evidence: applied, budget: expired)
        }
        #expect(throws: (any Error).self) {
            try ConsolidationReviewProposal(request: nil, operationId: operation, evidence: applied, budget: expired)
        }
    }

    @Test func proposalRevisionIsStableAcrossSavedEnumerationAndCaptureTime() throws {
        let fixture = try ConsolidationPreviewFixture()
        let original = try fixture.capture()
        let request = try ConsolidationPreviewInput.apply(fixture.arguments).0
        let graph = try TaskLinkGraph.project(tasks: original.graph.tasks.reversed(),
            occurrences: original.graph.occurrences.reversed(),
            removalEvidence: original.graph.removalEvidence.reversed(), evaluationInstant: Date.distantFuture)
        let reordered = ConsolidationSavedEvidence(selectedTaskIds: original.selectedTaskIds,
            originals: original.originals.reversed(), events: original.events.reversed(),
            history: original.history.reversed(), graph: graph, encodedByteCount: original.encodedByteCount)
        let proposal = try ConsolidationReviewProposal(request: request, operationId: nil, evidence: original)
        let equivalent = try ConsolidationReviewProposal(request: request, operationId: nil, evidence: reordered)
        #expect(try proposal.revision() == equivalent.revision())
        var ordered = request
        ordered = ConsolidationRequest(survivorTaskId: request.survivorTaskId,
            candidateTaskIds: request.candidateTaskIds.reversed(), reason: request.reason,
            preservation: request.preservation, survivorEdits: request.survivorEdits)
        #expect(try proposal.revision() != ConsolidationReviewProposal(request: ordered,
            operationId: nil, evidence: original).revision())
    }

    @Test func undoPreviewReadsPermanentRecordedChangesAndCurrentAssessment() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
                                                   fence: .actorOnlyTestFixture)
        let evidence = try capture.capture(selectedTaskIds: [fixture.base.source.id])
        let operation = try #require(evidence.events.first?.operationId)
        let data = try TaskConsolidationPreviewProjection.undo(operation, evidence: evidence)
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(result["operationId"] as? String == operation.uuidString)
        #expect(result["undoAvailable"] as? Bool == true)
        #expect((result["changes"] as? [[String: Any]])?.isEmpty == false)
        #expect(try fixture.base.owner.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 1)
        #expect(fixture.observation.commitSaves == 1)
    }
}
#endif
