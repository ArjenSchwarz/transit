#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkWriteRepairTests {
    @Test(arguments: ["self", "unknown", "dangling", "equivalent"])
    func exactRepairPreservesOtherPhysicalRowsAndSupportsFreshKeyNoOp(fault: String) async throws {
        let base = try TaskLinkCommitDiskFixture()
        let sourceID = base.source.id
        let targetID = base.target.id
        let edgeID = UUID()
        base.owner.context.delete(base.edge)
        let kind = fault == "unknown" ? "future-kind" : "dependency"
        let opposite = fault == "self" ? sourceID : (fault == "dangling" ? UUID() : targetID)
        let row = TaskLinkOccurrence(id: edgeID, kindRawValue: kind, sourceTaskID: sourceID,
                                     targetTaskID: opposite, createdAt: base.instant)
        base.owner.context.insert(row)
        let otherID = UUID()
        if fault == "equivalent" {
            base.owner.context.insert(TaskLinkOccurrence(id: otherID, kindRawValue: kind,
                sourceTaskID: sourceID, targetTaskID: opposite, createdAt: base.instant))
        }
        try base.owner.context.save()
        let fixture = TaskLinkWriteFixture(base: base)
        let value = TaskLinkOccurrenceValue(physicalKey: Data(), id: edgeID, kind: kind,
            source: sourceID, target: opposite, createdAt: base.instant)
        var args: [String: Any] = ["taskId": sourceID.uuidString, "expectedRevision": try fixture.revision(sourceID),
            "idempotencyKey": "repair", "linkChanges": [["action": "remove", "edgeId": edgeID.uuidString,
                "occurrenceRevision": try TaskLinkGraph.occurrenceRevision(value)]],
            "endpointPreconditions": fault == "self" || fault == "dangling" ? [] : [
                ["taskId": targetID.uuidString, "expectedRevision": try fixture.revision(targetID)]]]
        try fixture.assertOutcome(await fixture.execute(args), "committed")
        let observed = try base.observer()
        let edges = try observed.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == (fault == "equivalent" ? 1 : 0))
        #expect(edges.allSatisfy { $0.id == otherID })
        let before = try fixture.revision(sourceID)
        let evidence = try observed.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
            .filter { $0.edgeId == edgeID }
        let original = try #require(evidence.count == 1 ? evidence.first : nil)
        #expect(original.kindRawValue == kind && original.sourceTaskID == sourceID && original.targetTaskID == opposite)
        args["idempotencyKey"] = "repair-noop"
        args["expectedRevision"] = before
        args["endpointPreconditions"] = [] as [[String: String]]
        try fixture.assertOutcome(await fixture.execute(args), "committed")
        #expect(try fixture.revision(sourceID) == before)
        let reopened = try base.observer()
        let unchanged = try reopened.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
            .filter { $0.edgeId == edgeID }
        #expect(unchanged.count == 1 && unchanged.first?.id == original.id)
        #expect(unchanged.first?.removedAt == original.removedAt)
    }

    @Test func chosenCreationUUIDCollisionRejectsWithoutDomainInsertion() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let collision = base.source.id
        let fixture = TaskLinkWriteFixture(base: base, newTaskID: { collision })
        let projectID = try #require(base.source.project?.id)
        let args: [String: Any] = ["name": "collision", "type": "feature", "projectId": projectID.uuidString,
            "idempotencyKey": "collision", "linkChanges": [["action": "add", "type": "relates-to",
                "targetTaskId": base.target.id.uuidString]], "endpointPreconditions": [
                    ["taskId": base.target.id.uuidString, "expectedRevision": try fixture.revision(base.target.id)]]]
        let result = await fixture.execute(args, tool: "create_task")
        try fixture.assertOutcome(result, "rejected")
        #expect((try base.decode(result)["error"] as? [String: Any])?["code"] as? String
            == "DUPLICATE_TASK_IDENTIFIER")
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TransitTask>()) == 2)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try fixture.receipts(for: args, in: observer.context).first?.stateRawValue == "rejected")
    }

    @Test func retainedReplayDoesNotValidateOrSaveDirtyGraphDraft() async throws {
        let base = try TaskLinkCommitDiskFixture()
        var preparations = 0
        let fixture = TaskLinkWriteFixture(base: base, preparation: { _ in preparations += 1 })
        let args = try fixture.addition()
        let first = await fixture.execute(args)
        try fixture.assertOutcome(first, "committed")
        base.source.name = "unsaved source"
        base.owner.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "future-kind",
            sourceTaskID: base.source.id, targetTaskID: UUID(), createdAt: Date()))
        let replay = await fixture.execute(args)
        #expect(replay.content.first?.text == first.content.first?.text)
        #expect(preparations == 1 && base.source.name == "unsaved source" && base.owner.context.hasChanges)
        let observer = try base.observer()
        #expect(try base.task(base.source.id, in: observer.context).name == "source")
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 2)
    }
}
#endif
