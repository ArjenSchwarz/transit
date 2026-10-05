#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationOwnedCommitTests {
    @Test func coordinatorRecognizesProtectedGroupCommands() {
        #expect(MCPWriteCommand.protectedTools.contains("consolidate_tasks"))
        #expect(MCPWriteCommand.protectedTools.contains("undo_task_consolidation"))
    }

    @Test func groupHistoryAndReceiptShareOneOwnedSaveAndReopen() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        let result = await fixture.execute()
        #expect(try fixture.base.decode(result)["outcome"] as? String == "committed")
        #expect(fixture.observation.commitSaves == 1)
        #expect(fixture.observation.commitContext !== fixture.base.owner.context)
        let observer = try fixture.base.observer()
        for id in [fixture.base.source.id, fixture.extra.id] {
            let task = try fixture.base.task(id, in: observer.context)
            #expect(task.statusRawValue == "abandoned")
            #expect(task.lastStatusChangeDate == fixture.base.instant && task.completionDate == fixture.base.instant)
        }
        let survivor = try fixture.base.task(fixture.base.target.id, in: observer.context)
        #expect(survivor.statusRawValue == "done" && survivor.taskDescription == "reviewed survivor")
        let events = try observer.context.fetch(FetchDescriptor<TaskConsolidationEvent>())
        let event = try #require(events.count == 1 ? events.first : nil)
        let value = try TaskConsolidationEventValue.capture(event)
        let payload = try TaskConsolidationHistoryCodec.decode(value)
        #expect(payload.createdOccurrences.count == 2)
        for id in [fixture.base.source.id, fixture.base.target.id, fixture.extra.id] {
            let task = try fixture.base.task(id, in: observer.context)
            #expect(try MCPRecordSnapshot.task(task, in: observer.context).revision
                == payload.appliedRevisions[id.uuidString])
        }
        #expect(try fixture.base.decode(result)["operationRevision"] as? String
            == TaskConsolidationHistoryCodec.revision([value]))
        let receipts = try fixture.receipts(in: observer.context)
        #expect(receipts.count == 1 && receipts[0].stateRawValue == "committed")
        #expect(receipts[0].resultJSON == result.content.first?.text)
        #expect(try fixture.base.historicReceipt(in: observer.context).resultJSON == fixture.base.historicJSON)
        #expect(try observer.context.fetchCount(FetchDescriptor<Transit.Comment>()) == 1)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 3)
        #expect(!fixture.base.owner.context.hasChanges && !observer.context.hasChanges)
    }

    @Test func statusOnlyClosureRetainsLargeUnchangedCandidateContent() async throws {
        let fixture = try TaskConsolidationCommitFixture(fault: "large-unchanged")
        let result = await fixture.execute()
        #expect(try fixture.base.decode(result)["outcome"] as? String == "committed")
        let observer = try fixture.base.observer()
        let source = try fixture.base.task(fixture.base.source.id, in: observer.context)
        #expect(source.taskDescription == String(repeating: "x", count: 300_000))
        #expect(source.metadataJSON == fixture.base.source.metadataJSON)
        #expect(source.statusRawValue == "abandoned")
        let event = try #require(observer.context.fetch(FetchDescriptor<TaskConsolidationEvent>()).first)
        #expect(event.payloadJSON.utf8.count < 8_192)
        let payload = try TaskConsolidationHistoryCodec.decode(TaskConsolidationEventValue.capture(event))
        let sourceChange = try #require(payload.changes.first { $0.taskId == source.id })
        #expect(sourceChange.fields["description"] == nil && sourceChange.fields["metadataJSON"] == nil)
    }

    @Test(arguments: ["save", "encode", "capacity", "recovery", "interruption", "raw-review"])
    func failureHasNoGroupEffectsOrTruthfulUncertainty(fault: String) async throws {
        let fixture = try TaskConsolidationCommitFixture(fault: fault)
        let result = await fixture.execute()
        let envelope = try fixture.base.decode(result)
        #expect(envelope["outcome"] as? String == (fault == "recovery" ? "uncertain" : "rejected"))
        #expect(envelope["accepted"] as? Bool == true)
        let observer = try fixture.base.observer()
        #expect(try fixture.base.task(fixture.base.source.id, in: observer.context).statusRawValue == "idea")
        #expect(try fixture.base.task(fixture.extra.id, in: observer.context).statusRawValue == "planning")
        #expect(try fixture.base.task(fixture.base.target.id, in: observer.context).taskDescription == nil)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 1)
        let receipts = try fixture.receipts(in: observer.context)
        let receipt = try #require(receipts.count == 1 ? receipts.first : nil)
        #expect(receipt.stateRawValue == (fault == "recovery" ? "accepted" : "rejected"))
        #expect(try fixture.base.historicReceipt(in: observer.context).resultJSON == fixture.base.historicJSON)
        #expect(!fixture.base.owner.context.hasChanges)
    }

    @Test func durableCommitWithLostAcknowledgmentReplaysWithoutSecondEffects() async throws {
        let fixture = try TaskConsolidationCommitFixture(fault: "saved-throw")
        let result = await fixture.execute()
        #expect(try fixture.base.decode(result)["outcome"] as? String == "committed")
        let replay = await fixture.execute()
        #expect(result.content.first?.text == replay.content.first?.text)
        #expect(fixture.observation.commitSaves == 1)
        let observer = try fixture.base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 1)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 3)
    }

    @Test(arguments: ["participant", "history", "operation"])
    func malformedGroupTerminalCannotReplay(field: String) async throws {
        let fixture = try TaskConsolidationCommitFixture()
        let result = await fixture.execute()
        var envelope = try fixture.base.decode(result)
        switch field {
        case "participant": envelope["participants"] = [["taskId": fixture.extra.id.uuidString]]
        case "history": envelope["operationRevision"] = "o1:malformed"
        default: envelope["operationId"] = UUID().uuidString
        }
        let observer = try fixture.base.observer()
        let receipts = try fixture.receipts(in: observer.context)
        let receipt = try #require(receipts.count == 1 ? receipts.first : nil)
        receipt.resultJSON = try MCPWriteOutcome.encode(envelope)
        try observer.context.save()
        let replay = await fixture.execute()
        #expect(try fixture.base.decode(replay)["outcome"] as? String == "uncertain")
        #expect(fixture.observation.commitSaves == 1)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 1)
    }

    @Test(arguments: ["success", "error"])
    func postAwaitDraftsRemainUnsavedAndUnrolledBack(path: String) async throws {
        let fixture = try TaskConsolidationCommitFixture(fault: "dirty-" + path)
        let result = await fixture.execute()
        #expect(try fixture.base.decode(result)["outcome"] as? String == "uncertain")
        #expect(fixture.base.source.name == "UI draft" && fixture.base.owner.context.hasChanges)
        #expect(fixture.observation.commitSaves == 0)
        let observer = try fixture.base.observer()
        #expect(try fixture.base.task(fixture.base.source.id, in: observer.context).name == "source")
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "accepted")
    }

    @Test func dirtyReplayAndFreshDirtyWorkNeverSaveDrafts() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        let committed = await fixture.execute()
        fixture.base.source.name = "UI draft"
        let replay = await fixture.execute()
        #expect(replay.content.first?.text == committed.content.first?.text)
        let fresh = await fixture.execute(key: "new-dirty")
        #expect(try fixture.base.decode(fresh)["outcome"] as? String == "uncertain")
        #expect(fixture.base.source.name == "UI draft" && fixture.base.owner.context.hasChanges)
        #expect(fixture.observation.commitSaves == 1)
        let observer = try fixture.base.observer()
        #expect(try fixture.base.task(fixture.base.source.id, in: observer.context).name == "source")
        #expect(try fixture.receipts(in: observer.context).count == 1)
    }

    @Test func participatingRequestsRevalidateBeforeSecondGroupSave() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        async let first = fixture.execute(key: "first-group")
        async let second = fixture.execute(key: "second-group")
        let outcomes = try await [first, second].map { try fixture.base.decode($0)["outcome"] as? String ?? "missing" }
        #expect(outcomes.sorted() == ["committed", "rejected"])
        #expect(fixture.observation.commitSaves == 1)
        let observer = try fixture.base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 1)
        let receipts = try fixture.receipts(in: observer.context)
        #expect(receipts.count == 2)
        let conflict = try #require(receipts.first { $0.stateRawValue == "rejected" }?.resultJSON)
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(conflict.utf8)) as? [String: Any])
        #expect((envelope["affectedTaskIds"] as? [String])?.count == 3)
        #expect((envelope["currentRevisions"] as? [String: String])?.count == 3)
        #expect(envelope["currentRecord"] == nil)
    }

    @Test func missingOwnedCapabilityCannotBypassProtection() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        let result = await fixture.coordinator.execute(tool: "consolidate_tasks", arguments: fixture.arguments())
        #expect(try fixture.base.decode(result)["outcome"] as? String == "rejected")
        #expect(try fixture.base.decode(result)["accepted"] as? Bool == false)
        #expect(fixture.observation.commitSaves == 0)
        let observer = try fixture.base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        #expect(try fixture.receipts(in: observer.context).isEmpty)
    }
}

@MainActor final class TaskConsolidationCommitObservation {
    var commitSaves = 0
    var commitContext: ModelContext?
}

@MainActor struct TaskConsolidationCommitFixture {
    let base: TaskLinkCommitDiskFixture
    let extra: TransitTask
    let coordinator: MCPWriteCoordinator
    let adapter: MCPConsolidationWriteAdapter
    let review: TaskConsolidationOwnedReview
    let observation = TaskConsolidationCommitObservation()

    init(fault: String = "none") throws {
        let base = try TaskLinkCommitDiskFixture()
        self.base = base
        extra = try Self.seedExtra(base, fault: fault)
        let ids = [base.target.id, base.source.id, extra.id]
        let reviewId = UUID(), revision = "p1:" + String(repeating: "a", count: 64)
        let values = try Self.reviewPayload(base: base, extra: extra, fault: fault,
            id: reviewId, revision: revision)
        let observation = self.observation
        coordinator = base.coordinator(save: { context, stage in
            if case .commit = stage {
                observation.commitSaves += 1
                observation.commitContext = context
                if ["save", "recovery"].contains(fault) { throw TaskLinkCommitDiskFixture.Failure.injected }
            }
            try context.save()
            if case .commit = stage, fault == "saved-throw" { throw TaskLinkCommitDiskFixture.Failure.injected }
        }, encode: { envelope in
            if fault == "encode", envelope["outcome"] as? String == "committed" {
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
            return try MCPWriteOutcome.encode(envelope)
        }, preparation: { _ in
            if fault.hasPrefix("dirty-") {
                base.source.name = "UI draft"
                if fault == "dirty-error" { throw TaskLinkCommitDiskFixture.Failure.injected }
            }
            if fault == "interruption" { throw CancellationError() }
        }, recovery: {
            if fault == "recovery" { throw TaskLinkCommitDiskFixture.Failure.injected }
        })
        let scope = try #require(coordinator.localScopeId)
        review = TaskConsolidationOwnedReview(id: reviewId, revision: revision, originScopeId: scope,
            payload: values.payload, changes: values.changes, expectedRevisions: values.revisions,
            links: TaskLinkPlan(removals: [], additions: [base.source.id, extra.id].map {
                TaskLinkPlannedAddition(relation:
                    TaskLinkType.duplicateOf.normalized(source: $0, target: base.target.id))
            }, affectedEndpoints: Set(ids)))
        let retained = review
        adapter = MCPConsolidationWriteAdapter(taskAllocator: base.allocator, milestoneAllocator: base.allocator,
            configuration: TaskConsolidationService.Configuration(originScopeId: scope,
                reviewSource: { id, _ in
                    guard id == retained.id else { throw TaskLinkCommitDiskFixture.Failure.injected }
                    return retained
                }, clock: { base.instant }))
    }

    private static func seedExtra(_ base: TaskLinkCommitDiskFixture, fault: String) throws -> TransitTask {
        if fault == "large-unchanged" {
            base.source.taskDescription = String(repeating: "x", count: 300_000)
            base.source.metadataJSON = "{\"retained\":\"" + String(repeating: "m", count: 300_000) + "\"}"
            try base.owner.context.save()
        }

        let extra = TransitTask(name: "second candidate", type: .feature, project: try #require(base.source.project),
            displayID: .permanent(3))
        extra.statusRawValue = "planning"
        extra.metadataJSON = "{ \"retained\" : \"raw bytes\" }"
        base.owner.context.insert(extra)
        let comment = Transit.Comment(content: "original comment", authorName: "Original author", isAgent: true,
            task: base.source)
        comment.creationDate = base.instant
        base.owner.context.insert(comment)
        try base.owner.context.save()
        return extra
    }

    private struct ReviewValues {
        let payload: TaskConsolidationPayload
        let revisions: [UUID: String]
        let changes: [TaskConsolidationReviewedTaskChange]
    }

    private static func reviewPayload(base: TaskLinkCommitDiskFixture, extra: TransitTask, fault: String,
                                      id reviewId: UUID, revision: String)
        throws -> ReviewValues {
        let revisions = try Dictionary(uniqueKeysWithValues: [base.target, base.source, extra].map {
            ($0.id, try MCPRecordSnapshot.task($0, in: base.owner.context).revision)
        })
        let changes = try [base.target, base.source, extra].map { task in
            let raw = try TaskConsolidationRawFields.capture(task)
            let before = TaskConsolidationRawFields(description:
                fault == "raw-review" && task.id == base.source.id ? "stale transient field" : raw.description,
                metadataJSON: raw.metadataJSON, statusRawValue: raw.statusRawValue,
                lastStatusChangeDate: raw.lastStatusChangeDate, completionDate: raw.completionDate)
            let survivor = task.id == base.target.id
            let after = TaskConsolidationRawFields(description: survivor ? "reviewed survivor" : before.description,
                metadataJSON: before.metadataJSON, statusRawValue: survivor ? before.statusRawValue : "abandoned",
                lastStatusChangeDate: before.lastStatusChangeDate, completionDate: before.completionDate)
            return TaskConsolidationReviewedTaskChange(taskId: task.id, before: before, after: after)
        }
        let preservation = Dictionary(uniqueKeysWithValues: [base.source.id, extra.id].map {
            ($0.uuidString, ["retainedExplanation": "original detail retained"])
        })
        let preservationData = try JSONSerialization.data(withJSONObject: preservation)
        let preservationJSON = try #require(String(data: preservationData, encoding: .utf8))
        let payload = TaskConsolidationPayload(operationId: UUID(), kind: "apply", survivorTaskId: base.target.id,
            candidateTaskIds: [base.source.id, extra.id],
            reason: fault == "capacity" ? String(repeating: "é", count: 256 * 1_024) : "reviewed equivalent work",
            preservationJSON: preservationJSON,
            changes: changes.map(\.delta),
            appliedRevisions: Dictionary(uniqueKeysWithValues: revisions.map { ($0.key.uuidString, $0.value) }),
            createdOccurrences: [], retainedOccurrences: [], requestKey: "group", reviewId: reviewId,
            reviewRevision: revision)
        return ReviewValues(payload: payload, revisions: revisions, changes: changes)
    }

    func arguments(key: String = "group") -> [String: Any] {
        ["idempotencyKey": key, "reviewId": review.id.uuidString, "reviewRevision": review.revision,
         "preservationAcknowledged": true]
    }

    func execute(key: String = "group") async -> MCPToolResult {
        await coordinator.execute(tool: "consolidate_tasks", arguments: arguments(key: key),
            batchPolicy: adapter.policy())
    }

    func receipts(in context: ModelContext) throws -> [MCPWriteReceipt] {
        let tool = "consolidate_tasks"
        return try context.fetch(FetchDescriptor<MCPWriteReceipt>(predicate: #Predicate { $0.tool == tool }))
    }
}
#endif
