#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkWriteIntegrationTests {
    @Test(arguments: ["relates-to", "introduced-by", "duplicate-of"])
    func mixedFieldsAndLinkCommitWithCoveredTerminalReceipt(type: String) async throws {
        let base = try TaskLinkCommitDiskFixture()
        let fixture = TaskLinkWriteFixture(base: base)
        let sourceProject = base.source.project?.id
        let targetDate = base.target.lastStatusChangeDate
        var args = try fixture.addition(type: type)
        args["name"] = "mixed committed"
        let result = await fixture.execute(args)
        try fixture.assertOutcome(result, "committed")
        let observer = try base.observer()
        let source = try base.task(base.source.id, in: observer.context)
        let target = try base.task(base.target.id, in: observer.context)
        #expect(source.name == "mixed committed" && source.project?.id == sourceProject)
        #expect(target.name == "target" && target.statusRawValue == "done" && target.lastStatusChangeDate == targetDate)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 2)
        let record = try #require(try base.decode(result)["record"] as? [String: Any])
        #expect(record["revision"] as? String == (try MCPRecordSnapshot.task(source, in: observer.context).revision))
        #expect(try base.receipts(in: observer.context).first?.resultJSON == result.content.first?.text)
        #expect(try base.historicReceipt(in: observer.context).resultJSON == base.historicJSON)
    }

    @Test func createUsesItsFinalUUIDForProposedGraphAndOwnedSave() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let fixture = TaskLinkWriteFixture(base: base)
        let projectID = try #require(base.source.project?.id)
        let args: [String: Any] = ["name": "linked creation", "type": "feature", "projectId": projectID.uuidString,
            "idempotencyKey": "created-link", "linkChanges": [["action": "add", "type": "blocked-by",
                "targetTaskId": base.target.id.uuidString]], "endpointPreconditions": [
                    ["taskId": base.target.id.uuidString, "expectedRevision": try fixture.revision(base.target.id)]]]
        let result = await fixture.execute(args, tool: "create_task")
        try fixture.assertOutcome(result, "committed")
        let record = try #require(try base.decode(result)["record"] as? [String: Any])
        let id = try #require((record["taskId"] as? String).flatMap(UUID.init(uuidString:)))
        #expect(id != base.source.id && id != base.target.id)
        let observer = try base.observer()
        let created = try base.task(id, in: observer.context)
        #expect(created.name == "linked creation" && created.project?.id == projectID)
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.filter { $0.sourceTaskID == base.target.id && $0.targetTaskID == id }.count == 1)
        #expect(record["revision"] as? String == (try MCPRecordSnapshot.task(created, in: observer.context).revision))
        let replay = await fixture.execute(args, tool: "create_task")
        #expect(replay.content.first?.text == result.content.first?.text)
        #expect(try observer.context.fetchCount(FetchDescriptor<TransitTask>()) == 3)
    }

    @Test func existingAdditionIsProtectedNoOpWithoutExtraEndpointGuard() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let fixture = TaskLinkWriteFixture(base: base)
        var args = try fixture.addition(type: "blocked-by")
        args["endpointPreconditions"] = [] as [[String: String]]
        let before = try fixture.revision(base.source.id)
        let result = await fixture.execute(args)
        try fixture.assertOutcome(result, "committed")
        #expect(try fixture.revision(base.source.id) == before)
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try base.receipts(in: observer.context).count == 1)
        let replay = await fixture.execute(args)
        #expect(replay.content.first?.text == result.content.first?.text)
    }

    @Test func exactRemovalFreshKeyNoOpAndReAddPreserveOriginalEvidence() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let fixture = TaskLinkWriteFixture(base: base)
        let args = try fixture.removal()
        let first = await fixture.execute(args)
        try fixture.assertOutcome(first, "committed")
        let observer = try base.observer()
        let evidence = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
            .filter { $0.edgeId == base.edge.id }
        let original = try #require(evidence.count == 1 ? evidence.first : nil)
        var retry = args
        retry["idempotencyKey"] = "fresh-removal-noop"
        retry["expectedRevision"] = try fixture.revision(base.source.id)
        retry["endpointPreconditions"] = [] as [[String: String]]
        try fixture.assertOutcome(await fixture.execute(retry), "committed")
        let unchanged = try base.observer().context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
            .filter { $0.edgeId == base.edge.id }
        #expect(unchanged.count == 1 && unchanged.first?.id == original.id)
        #expect(unchanged.first?.removedAt == original.removedAt)
        let reAdd = try fixture.addition(type: "blocked-by", key: "re-add")
        try fixture.assertOutcome(await fixture.execute(reAdd), "committed")
        let reopened = try base.observer()
        let edges = try reopened.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id != base.edge.id)
        let replay = await fixture.execute(args)
        #expect(replay.content.first?.text == first.content.first?.text)
    }

    @Test func removalOnlyRepairsExactRowWithoutAbsorbingUnrelatedCorruption() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let unrelated = UUID()
        base.owner.context.insert(TaskLinkOccurrence(id: unrelated, kindRawValue: "future-kind",
            sourceTaskID: base.source.id, targetTaskID: UUID(), createdAt: base.instant))
        try base.owner.context.save()
        let fixture = TaskLinkWriteFixture(base: base)
        let args = try fixture.removal()
        let result = await fixture.execute(args)
        try fixture.assertOutcome(result, "committed")
        let observer = try base.observer()
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id == unrelated && edges.first?.kindRawValue == "future-kind")
        #expect(try base.task(base.source.id, in: observer.context).name == "source")
    }

    @Test(arguments: ["source", "endpoint"])
    func savedRevisionChangeDuringPreparationRejectsBeforeGraphApply(changed: String) async throws {
        let base = try TaskLinkCommitDiskFixture()
        let peer = try base.observer()
        let fixture = TaskLinkWriteFixture(base: base, preparation: { _ in
            let id = changed == "source" ? base.source.id : base.target.id
            try base.task(id, in: peer.context).name = "outside saved change"
            try peer.context.save()
        })
        let args = try fixture.addition()
        let result = await fixture.execute(args)
        try fixture.assertOutcome(result, "rejected")
        let decoded = try base.decode(result)
        #expect((decoded["error"] as? [String: Any])?["code"] as? String == "REVISION_CONFLICT")
        #expect((decoded["currentRecord"] as? [String: Any])?["graphCoverage"] as? String == "available")
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try base.receipts(in: observer.context).first?.stateRawValue == "rejected")
    }

    @Test(arguments: ["cycle", "missing"])
    func validShapeDomainRejectionRetainsKeyAndNoDomainEffects(fault: String) async throws {
        let base = try TaskLinkCommitDiskFixture()
        let fixture = TaskLinkWriteFixture(base: base)
        var args = try fixture.addition(type: "blocks")
        if fault == "missing" {
            let absent = UUID()
            args["linkChanges"] = [["action": "add", "type": "relates-to", "targetTaskId": absent.uuidString]]
            args["endpointPreconditions"] = [["taskId": absent.uuidString,
                "expectedRevision": "r1:" + String(repeating: "a", count: 64)]]
        }
        let first = await fixture.execute(args)
        try fixture.assertOutcome(first, "rejected")
        #expect((try base.decode(first)["error"] as? [String: Any])?["code"] as? String != "PERSISTENCE_UNAVAILABLE")
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try base.receipts(in: observer.context).first?.resultJSON == first.content.first?.text)
        let replay = await fixture.execute(args)
        #expect(first.content.first?.text == replay.content.first?.text)
    }

    @Test(arguments: ["save", "encode"])
    func failedTerminalCommitRollsBackFieldsAndGraphTogether(failure: String) async throws {
        let base = try TaskLinkCommitDiskFixture()
        let fixture = TaskLinkWriteFixture(base: base, save: { context, stage in
            if case .commit = stage, failure == "save" { throw TaskLinkCommitDiskFixture.Failure.injected }
            try context.save()
        }, encode: { envelope in
            if failure == "encode", envelope["outcome"] as? String == "committed" {
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
            return try MCPWriteOutcome.encode(envelope)
        })
        var args = try fixture.addition()
        args["name"] = "must rollback"
        let result = await fixture.execute(args)
        try fixture.assertOutcome(result, "rejected")
        let observer = try base.observer()
        #expect(try base.task(base.source.id, in: observer.context).name == "source")
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try base.receipts(in: observer.context).first?.stateRawValue == "rejected")
    }

    @Test(arguments: [false, true])
    func dirtyAfterPreparationPreservesDraftAndAcceptedReconciliation(throwing: Bool) async throws {
        let base = try TaskLinkCommitDiskFixture()
        var prepared = false
        let fixture = TaskLinkWriteFixture(base: base, preparation: { _ in
            prepared = true
            base.source.name = "UI draft"
            if throwing { throw TaskLinkCommitDiskFixture.Failure.injected }
        })
        let args = try fixture.addition()
        let result = await fixture.execute(args)
        try fixture.assertOutcome(result, "uncertain")
        #expect(prepared && base.source.name == "UI draft" && base.owner.context.hasChanges)
        let observer = try base.observer()
        #expect(try base.task(base.source.id, in: observer.context).name == "source")
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        #expect(try base.receipts(in: observer.context).first?.stateRawValue == "accepted")
    }
}
#endif
