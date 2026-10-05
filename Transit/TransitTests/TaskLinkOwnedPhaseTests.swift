#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkOwnedPhaseTests {
    @Test func sourceConflictPreventsGraphCallback() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        var calls = 0
        var arguments = try fixture.updateArguments()
        arguments["expectedRevision"] = "r1:" + String(repeating: "0", count: 64)
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices,
            afterTaskApply: { _, _, _ in calls += 1 })
        let result = await fixture.coordinator(save: { context, _ in try context.save() }).execute(
            tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        #expect(calls == 0)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
    }

    @Test func terminalSnapshotIncludesOwnedGraphAndReplayDoesNotRunCallback() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let inserted = UUID(), evidence = UUID()
        var calls = 0
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices,
            afterTaskApply: { _, task, services in
                #expect(task.modelContext === services.context)
                calls += 1
                try fixture.stageGraph(context: services.context, insertedID: inserted, evidenceID: evidence)
            })
        let arguments = try fixture.updateArguments()
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() })
        let first = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(try fixture.decode(first)["outcome"] as? String == "committed")
        let observer = try fixture.observer()
        let saved = try fixture.task(fixture.source.id, in: observer.context)
        let record = try #require(try fixture.decode(first)["record"] as? [String: Any])
        #expect(record["revision"] as? String == (try MCPRecordSnapshot.task(saved, in: observer.context).revision))
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(first.content.first?.text == replay.content.first?.text)
        #expect(calls == 1)
    }

    @Test(arguments: ["callback", "save", "encode"])
    func ownedGraphDomainAndReceiptStayAllOrNoneAfterCallback(failure: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let inserted = UUID(), evidence = UUID()
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices,
            afterTaskApply: { _, _, services in
                try fixture.stageGraph(context: services.context, insertedID: inserted, evidenceID: evidence)
                if failure == "callback" { throw TaskLinkCommitDiskFixture.Failure.injected }
            })
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage, failure == "save" { throw TaskLinkCommitDiskFixture.Failure.injected }
            try context.save()
        }, encode: { envelope in
            if failure == "encode", envelope["outcome"] as? String == "committed" {
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
            return try MCPWriteOutcome.encode(envelope)
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        #expect(!fixture.owner.context.hasChanges)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id == fixture.edge.id)
        let removals = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(!removals.contains { $0.id == evidence })
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "rejected")
    }
}
#endif
