#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit
@MainActor @Suite(.serialized) struct MCPConsolidationReceiptTests {
    @Test(arguments: ["forward-undo", "participants", "operation", "history-kind"])
    func malformedImportedGroupTerminalFailsClosed(fault: String) async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        _ = await fixture.apply(try await fixture.previewApply())
        let operation = try #require(try fixture.capture().events.first?.operationId)
        _ = await fixture.undo(try await fixture.previewUndo(operation))
        let owner = try fixture.preview.base.base.observer()
        let context = owner.context
        let store = MCPWriteReceiptStore(context: context, scopeID: fixture.preview.scope)
        let receipt = try #require(try store.lookup(tool: "undo_task_consolidation", key: "reviewed-undo"))
        try store.validate(receipt)
        let terminal = try #require(receipt.resultJSON)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(terminal.utf8)) as? [String: Any])
        var history = try #require(envelope["history"] as? [String: Any])
        if fault == "participants" { envelope["participants"] = [] }
        if fault == "operation" { history["operationId"] = UUID().uuidString }
        if fault == "forward-undo" {
            var reversal = try #require(history["reversal"] as? [String: Any])
            reversal["changes"] = (history["apply"] as? [String: Any])?["changes"]
            history["reversal"] = reversal
        }
        if fault == "history-kind" {
            var apply = try #require(history["apply"] as? [String: Any])
            apply["kind"] = "future-kind"
            history["apply"] = apply
        }
        envelope["history"] = history
        receipt.resultJSON = try #require(String(data: JSONSerialization.data(withJSONObject: envelope),
            encoding: .utf8))
        #expect(throws: (any Error).self) { try store.validate(receipt) }
        #expect(try fixture.capture().events.count == 2)
    }
    @Test func knownUndoKindCannotReplacePrelinkedApplyHistory() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let context = fixture.preview.base.base.owner.context
        for id in fixture.candidates {
            context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate", sourceTaskID: id,
                targetTaskID: fixture.survivor, createdAt: Date(timeIntervalSinceReferenceDate: 41)))
        }
        try context.save()
        let applied = try fixture.decode(await fixture.apply(try await fixture.previewApply()))
        #expect(applied["outcome"] as? String == "committed")
        let owner = try fixture.preview.base.base.observer()
        let store = MCPWriteReceiptStore(context: owner.context, scopeID: fixture.preview.scope)
        let receipt = try #require(try store.lookup(tool: "consolidate_tasks", key: "reviewed-apply"))
        try store.validate(receipt)
        let terminal = try #require(receipt.resultJSON)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(terminal.utf8)) as? [String: Any])
        var history = try #require(envelope["history"] as? [String: Any])
        var apply = try #require(history["apply"] as? [String: Any])
        #expect((apply["createdOccurrences"] as? [Any])?.isEmpty == true)
        apply["kind"] = "undo"
        history["apply"] = apply
        envelope["history"] = history
        let bytes = try JSONSerialization.data(withJSONObject: envelope)
        receipt.resultJSON = try #require(String(data: bytes, encoding: .utf8))
        #expect(throws: (any Error).self) { try store.validate(receipt) }
        #expect(try fixture.capture().events.count == 1 && fixture.preview.base.observation.commitSaves == 1)
    }

    @Test func completeTerminalRepresentationIsChargedBeforeSave() throws {
        let fixture = try TaskConsolidationCommitFixture()
        let receipt = MCPWriteReceipt(localScopeID: fixture.review.originScopeId, tool: "consolidate_tasks",
            key: "limit", requestJSON: "{}", acceptedAt: Date())
        let small = "{\"outcome\":\"committed\",\"detail\":\"small\"}"
        try MCPConsolidationTerminalBudget.validate(small, receipt: receipt)
        let large = "{\"outcome\":\"committed\",\"detail\":\"" + String(repeating: "x",
            count: 4 * 1_024 * 1_024) + "\"}"
        #expect(throws: (any Error).self) { try MCPConsolidationTerminalBudget.validate(large, receipt: receipt) }
        #expect(fixture.observation.commitSaves == 0)
        #expect(receipt.resultJSON == nil && receipt.stateRawValue == "accepted")
    }
}
#endif
