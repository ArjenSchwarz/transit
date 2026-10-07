#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationConcurrencyTests {
    @Test(arguments: ["apply", "undo"])
    func competingApplyAndUndoRevalidateBeforeEffects(winner: String) async throws {
        let gate = MCPWritePreparationGate()
        let fixture = try ConsolidationReviewedCommitFixture(preparation: { command in
            if command.key == "parked" { await gate.park() }
        })
        let original = try fixture.capture()
        let initial = await fixture.apply(try await fixture.previewApply())
        #expect(try fixture.decode(initial)["outcome"] as? String == "committed")
        let operation = try #require(try fixture.capture().events.first?.operationId)
        var undo = try await fixture.previewUndo(operation)
        var apply = try await fixture.previewApply(description: "competing reviewed survivor detail")
        apply["idempotencyKey"] = winner == "apply" ? "winner" : "parked"
        undo["idempotencyKey"] = winner == "undo" ? "winner" : "parked"
        let applyReference = apply, undoReference = undo
        let blocked = Task {
            await (winner == "apply" ? fixture.undo(undoReference) : fixture.apply(applyReference))
        }
        await gate.waitForStart()
        let winning = await (winner == "apply" ? fixture.apply(applyReference) : fixture.undo(undoReference))
        let savedWinner: ConsolidationSavedEvidence
        do { savedWinner = try fixture.capture() } catch {
            await gate.release()
            _ = await blocked.value
            throw error
        }
        await gate.release()
        let losing = await blocked.value
        #expect(try fixture.decode(winning)["outcome"] as? String == "committed")
        #expect(try fixture.decode(losing)["outcome"] as? String == "rejected")
        try assertSameDomain(savedWinner, fixture.capture())
        try assertWinner(winner, fixture: fixture, original: original, operation: operation)
        let applyReplay = await fixture.apply(applyReference)
        let undoReplay = await fixture.undo(undoReference)
        #expect(applyReplay.content.first?.text == (winner == "apply" ? winning : losing).content.first?.text)
        #expect(undoReplay.content.first?.text == (winner == "undo" ? winning : losing).content.first?.text)
        try assertSameDomain(savedWinner, fixture.capture())
        #expect(fixture.preview.base.observation.commitSaves == 2)
    }

    private func assertSameDomain(_ expected: ConsolidationSavedEvidence,
                                  _ actual: ConsolidationSavedEvidence) throws {
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(expected.originals, actual.originals))
        try assertOccurrences(expected.graph.occurrences, actual.graph.occurrences)
        try assertRemovals(expected.graph.removalEvidence, actual.graph.removalEvidence)
        #expect(Dictionary(uniqueKeysWithValues: expected.events.map { ($0.id, $0.payloadJSON) })
            == Dictionary(uniqueKeysWithValues: actual.events.map { ($0.id, $0.payloadJSON) }))
    }

    private func assertWinner(_ winner: String, fixture: ConsolidationReviewedCommitFixture,
                              original: ConsolidationSavedEvidence, operation: UUID) throws {
        let saved = try fixture.capture()
        #expect(saved.events.count == 2)
        let history = try TaskConsolidationHistoryCodec.history(saved.events.filter {
            $0.operationId == operation
        }, operationId: operation)
        if winner == "apply" {
            #expect(history.reversal == nil && saved.events.allSatisfy { $0.kind == "apply" })
            #expect(saved.originals.first { $0.id == fixture.survivor }?.fields.description
                == "competing reviewed survivor detail")
        } else {
            #expect(history.reversal != nil)
            #expect(try ConsolidationPreviewFixture.sameSavedOriginals(original.originals, saved.originals))
            try assertOccurrences(original.graph.occurrences, saved.graph.occurrences)
        }
    }

    private func assertOccurrences(_ expected: [TaskLinkOccurrenceValue],
                                   _ actual: [TaskLinkOccurrenceValue]) throws {
        #expect(expected.count == actual.count)
        let before = expected.sorted { $0.id.uuidString < $1.id.uuidString }
        let after = actual.sorted { $0.id.uuidString < $1.id.uuidString }
        for (left, right) in zip(before, after) {
            try assertPhysicalIdentity(left.physicalKey, right.physicalKey)
            #expect(try TaskLinkGraph.occurrenceRevision(left) == TaskLinkGraph.occurrenceRevision(right))
        }
    }

    private func assertRemovals(_ expected: [TaskLinkRemovalValue], _ actual: [TaskLinkRemovalValue]) throws {
        #expect(expected.count == actual.count)
        let before = expected.sorted { $0.id.uuidString < $1.id.uuidString }
        let after = actual.sorted { $0.id.uuidString < $1.id.uuidString }
        for (left, right) in zip(before, after) {
            try assertPhysicalIdentity(left.physicalKey, right.physicalKey)
            #expect(left.id == right.id && left.edgeId == right.edgeId && left.kind == right.kind)
            #expect(left.source == right.source && left.target == right.target)
            #expect(left.occurrenceRevision == right.occurrenceRevision)
            #expect(try TaskConsolidationRawFields.exactDate(left.createdAt)
                == TaskConsolidationRawFields.exactDate(right.createdAt))
            #expect(try TaskConsolidationRawFields.exactDate(left.removedAt)
                == TaskConsolidationRawFields.exactDate(right.removedAt))
        }
    }

    private func assertPhysicalIdentity(_ expected: Data, _ actual: Data) throws {
        #expect(try JSONDecoder().decode(PersistentIdentifier.self, from: expected)
            == JSONDecoder().decode(PersistentIdentifier.self, from: actual))
    }

}
#endif
