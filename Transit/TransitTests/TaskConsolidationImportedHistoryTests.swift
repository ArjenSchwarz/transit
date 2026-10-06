#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationImportedHistoryTests {
    @Test func malformedImportedApplyRejectsPreviewAndOwnedUndoWithoutEffects() async throws {
        let fixture = try ConsolidationReviewedCommitFixture()
        let workflow = try ConsolidationAppWorkflowFixture(fixture: fixture.preview)
        _ = await fixture.apply(try await fixture.previewApply())
        let operation = try #require(try fixture.capture().events.first?.operationId)
        let reference = try await fixture.previewUndo(operation)
        try forgeCandidateDescription(fixture)
        let before = try savedValues(fixture)
        let receipts = try receiptCount(fixture)
        let preview = try await workflow.read("preview_task_consolidation_undo",
            ["operationId": operation.uuidString, "readPolicy": "cached"])
        #expect((preview["error"] as? [String: Any])?["code"] as? String == "CONSOLIDATION_HISTORY_UNAVAILABLE")
        #expect(try savedValues(fixture) == before)
        #expect(try receiptCount(fixture) == receipts)
        let result = try fixture.decode(await fixture.undo(reference))
        #expect(result["outcome"] as? String == "rejected" && result["accepted"] as? Bool == true)
        #expect(try receiptCount(fixture) == receipts + 1)
        #expect((result["error"] as? [String: Any])?["code"] as? String == "CONSOLIDATION_HISTORY_UNAVAILABLE")
        #expect(try savedValues(fixture) == before)
        #expect(fixture.preview.base.observation.commitSaves == 1)
    }

    private func forgeCandidateDescription(_ fixture: ConsolidationReviewedCommitFixture) throws {
        let owner = try fixture.preview.base.base.observer()
        let context = owner.context
        let event = try #require(context.fetch(FetchDescriptor<TaskConsolidationEvent>()).first)
        var document = try #require(JSONSerialization.jsonObject(with: Data(event.payloadJSON.utf8))
            as? [String: Any])
        var changes = try #require(document["changes"] as? [[String: Any]])
        let index = try #require(changes.firstIndex { $0["taskId"] as? String == fixture.candidates[0].uuidString })
        var fields = try #require(changes[index]["fields"] as? [String: Any])
        fields["description"] = ["before": "original", "after": "forged"]
        changes[index]["fields"] = fields
        document["changes"] = changes
        let json = try #require(String(data: JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]),
            encoding: .utf8))
        let replacement = TaskConsolidationEvent(id: event.id, operationId: event.operationId,
            kindRawValue: event.kindRawValue, createdAt: event.createdAt, originScopeId: event.originScopeId,
            survivorTaskId: event.survivorTaskId,
            candidateTaskIds: [event.candidate1, event.candidate2, event.candidate3, event.candidate4,
                               event.candidate5].compactMap { $0 }, payloadJSON: json)
        context.delete(event)
        context.insert(replacement)
        try context.save()
    }

    private func receiptCount(_ fixture: ConsolidationReviewedCommitFixture) throws -> Int {
        let owner = try fixture.preview.base.base.observer()
        return try owner.context.fetchCount(FetchDescriptor<MCPWriteReceipt>())
    }

    private func savedValues(_ fixture: ConsolidationReviewedCommitFixture) throws -> [String] {
        let owner = try fixture.preview.base.base.observer()
        let context = owner.context
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var values = try context.fetch(FetchDescriptor<TransitTask>()).map { task in
            let raw = TaskConsolidationRawFields(description: task.taskDescription, metadataJSON: task.metadataJSON,
                statusRawValue: task.statusRawValue,
                lastStatusChangeDate: try TaskConsolidationRawFields.exactDate(task.lastStatusChangeDate),
                completionDate: try task.completionDate.map(TaskConsolidationRawFields.exactDate))
            return task.id.uuidString + ":" + (try encoder.encode(raw)).base64EncodedString()
        }
        values += try context.fetch(FetchDescriptor<TaskLinkOccurrence>()).map {
            "link:\($0.id):\($0.kindRawValue):\($0.sourceTaskID):\($0.targetTaskID):"
                + (try TaskConsolidationRawFields.exactDate($0.createdAt))
        }
        values += try context.fetch(FetchDescriptor<Transit.Comment>()).map { "comment:\($0.id):\($0.content)" }
        values += try context.fetch(FetchDescriptor<TaskConsolidationEvent>()).map {
            "event:\($0.id):\($0.payloadJSON)"
        }

        values.append("removals:\(try context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()))")
        return values.sorted()
    }
}
#endif
