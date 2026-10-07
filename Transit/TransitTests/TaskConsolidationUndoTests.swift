#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationUndoTests {
    @Test func wholeUndoRestoresExactRawFieldsAndOnlyRemovesCreatedOccurrences() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let before = try fixture.capture()
        let applyReference = try await fixture.previewApply()
        #expect(try fixture.decode(await fixture.apply(applyReference))["outcome"] as? String == "committed")
        let applied = try fixture.capture()
        let operation = try #require(applied.events.first?.operationId)
        let reference = try await fixture.previewUndo(operation)
        let result = await fixture.undo(reference)
        #expect(try fixture.decode(result)["outcome"] as? String == "committed")
        let restored = try fixture.capture()
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, restored.originals))
        let history = try TaskConsolidationHistoryCodec.history(restored.events, operationId: operation)
        let reversal = try #require(history.reversal)
        #expect(reversal.changes == history.apply.changes.map(\.inverse))
        #expect(reversal.removedOccurrences == history.apply.createdOccurrences)
        #expect(restored.graph.occurrences.count == before.graph.occurrences.count)
        #expect(fixture.preview.base.observation.commitSaves == 2)
        let observer = try fixture.preview.base.base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>())
            == before.graph.removalEvidence.count + history.apply.createdOccurrences.count)
        #expect(try observer.context.fetchCount(FetchDescriptor<Transit.Comment>()) == 1)
        #expect(try fixture.preview.base.base.historicReceipt(in: observer.context).resultJSON
            == fixture.preview.base.base.historicJSON)
        fixture.preview.store.clear()
        #expect(await fixture.undo(reference).content.first?.text == result.content.first?.text)
        #expect(fixture.preview.base.observation.commitSaves == 2)
    }

    @Test(arguments: ["description", "comment", "incidence", "canonical", "project"])
    func changedWholeUndoEvidenceRejectsWithoutPartialRestoration(fault: String) async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let apply = try await fixture.previewApply()
        _ = await fixture.apply(apply)
        let operation = try #require(try fixture.capture().events.first?.operationId)
        let reference = try await fixture.previewUndo(operation)
        try fixture.changeSavedEvidence(fault)
        let before = try fixture.capture()
        #expect(try fixture.decode(await fixture.undo(reference))["outcome"] as? String == "rejected")
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, fixture.capture().originals))
        #expect(try fixture.capture().events.count == 1 && fixture.preview.base.observation.commitSaves == 1)
    }

    @Test func freshKeyAlreadyReversedUsesPermanentHistoryAfterReviewClear() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let apply = try await fixture.previewApply()
        _ = await fixture.apply(apply)
        let operation = try #require(try fixture.capture().events.first?.operationId)
        var reference = try await fixture.previewUndo(operation)
        _ = await fixture.undo(reference)
        fixture.preview.store.clear()
        reference["idempotencyKey"] = "fresh-already-reversed"
        let before = try fixture.capture()
        let result = try fixture.decode(await fixture.undo(reference))
        #expect(result["outcome"] as? String == "committed" && result["alreadyReversed"] as? Bool == true)
        #expect(result["undoUnavailableReason"] as? String == "already_reversed")
        #expect(result["reversalId"] is String)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, fixture.capture().originals))
        #expect(try fixture.capture().events.count == 2)
    }

    @Test(arguments: ["name", "status"])
    func unrelatedSavedTaskChangesDoNotInvalidateWholeUndo(field: String) async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let unrelated = try fixture.seedUnrelated()
        _ = await fixture.apply(try await fixture.previewApply())
        let operation = try #require(try fixture.capture().events.first?.operationId)
        let reference = try await fixture.previewUndo(operation)
        try fixture.changeUnrelated(unrelated, field: field)
        #expect(try fixture.decode(await fixture.undo(reference))["outcome"] as? String == "committed")
    }

    @Test func wrongOperationCannotUseAnotherReversalReview() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let apply = try await fixture.previewApply()
        _ = await fixture.apply(apply)
        let operation = try #require(try fixture.capture().events.first?.operationId)
        var reference = try await fixture.previewUndo(operation)
        reference["operationId"] = UUID().uuidString
        #expect(try fixture.decode(await fixture.undo(reference))["outcome"] as? String == "rejected")
        #expect(fixture.preview.base.observation.commitSaves == 1)
    }
}

extension ConsolidationReviewedCommitFixture {
    func previewUndo(_ operationId: UUID) async throws -> [String: Any] {
        let result = try preview.payload(await preview.execute(tool: "preview_task_consolidation_undo",
            arguments: ["operationId": operationId.uuidString, "readPolicy": "cached"]))
        #expect(result["undoAvailable"] as? Bool == true)
        return ["operationId": operationId.uuidString, "reviewId": try #require(result["reviewId"] as? String),
            "reviewRevision": try #require(result["reviewRevision"] as? String), "idempotencyKey": "reviewed-undo"]
    }

    func undo(_ arguments: [String: Any]) async -> MCPToolResult {
        await preview.base.coordinator.execute(tool: "undo_task_consolidation", arguments: arguments,
            batchPolicy: adapter.policy())
    }
}
#endif
