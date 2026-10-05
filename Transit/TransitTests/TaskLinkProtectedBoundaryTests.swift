#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Actual imported clean policy and coordinator hooks. Staged graph rows are
/// test participants, not an implementation of the future graph write adapter.
@MainActor @Suite(.serialized)
struct TaskLinkProtectedBoundaryTests {
    @Test func dirtyBeforeAcceptanceDoesNotSaveOrReserve() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        fixture.source.name = "UI draft"
        var saves = 0
        let coordinator = fixture.coordinator(save: { context, _ in saves += 1; try context.save() })
        let bindings = try bindingBytes(fixture)
        let result = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: .init())
        #expect(try fixture.decode(result)["outcome"] as? String == "uncertain")
        #expect(saves == 0)
        #expect(try bindingBytes(fixture) == bindings)
        #expect(fixture.source.name == "UI draft")
        #expect(fixture.owner.context.hasChanges)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        #expect(try fixture.receipts(in: observer.context).isEmpty)
    }

    @Test(arguments: [false, true])
    func dirtyAfterPreparationSuccessOrErrorRetainsAcceptedWithoutTerminalSave(throwsError: Bool) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        var savesAfterDraft = 0
        var draftInserted = false
        let coordinator = fixture.coordinator(save: { context, _ in
            if draftInserted { savesAfterDraft += 1 }
            try context.save()
        }, preparation: { _ in
            await Task.yield()
            fixture.source.name = "during await draft"
            draftInserted = true
            if throwsError { throw TaskLinkCommitDiskFixture.Failure.injected }
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: .init())
        let envelope = try fixture.decode(result)
        #expect(envelope["outcome"] as? String == "uncertain")
        #expect(envelope["accepted"] as? Bool == true)
        #expect(savesAfterDraft == 0)
        #expect(fixture.source.name == "during await draft")
        #expect(fixture.owner.context.hasChanges)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let receipt = try #require(try fixture.receipts(in: observer.context).first)
        #expect(receipt.stateRawValue == "accepted")
        #expect(receipt.resultJSON == nil)
    }

    @Test func dirtyRetainedReplayBypassesRecoveryValidationAndAllSaves() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        var saves = 0, recoveries = 0, validations = 0
        let coordinator = fixture.coordinator(save: { context, _ in saves += 1; try context.save() },
                                              recovery: { recoveries += 1 })
        let policy = MCPBatchWritePolicy { _, _ in validations += 1 }
        let original = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(try fixture.decode(original)["outcome"] as? String == "committed")
        let beforeSaves = saves
        let bindings = try bindingBytes(fixture)
        try #require(!bindings.isEmpty)
        fixture.source.name = "unsaved replay draft"
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(replay.content.first?.text == original.content.first?.text)
        #expect(saves == beforeSaves)
        #expect(recoveries == 0)
        #expect(validations == 1)
        #expect(try bindingBytes(fixture) == bindings)
        #expect(fixture.source.name == "unsaved replay draft")
        #expect(fixture.owner.context.hasChanges)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "committed update")
    }

    @Test func freshSavedEndpointValidationRejectsPeerChangeBeforeApply() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let peer = try fixture.observer()
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() }, preparation: { _ in
            let target = try fixture.task(fixture.target.id, in: peer.context)
            target.statusRawValue = "abandoned"
            try peer.context.save()
        })
        let policy = MCPBatchWritePolicy { _, _ in
            let fresh = try fixture.observer()
            guard try fixture.task(fixture.target.id, in: fresh.context).statusRawValue == "done" else {
                throw MCPWriteFailure("GRAPH_CONFLICT", "Test endpoint changed")
            }
        }
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        #expect(try fixture.task(fixture.target.id, in: observer.context).statusRawValue == "abandoned")
        #expect(try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>()).count == 1)
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "rejected")
    }

    @Test(arguments: ["save", "encode", "uncertain"])
    func stagedGraphAndTerminalReceiptShareFailureOutcome(failure: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let insertedID = UUID(), evidenceID = UUID()
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage, failure != "encode" { throw TaskLinkCommitDiskFixture.Failure.injected }
            try context.save()
        }, encode: { envelope in
            if envelope["outcome"] as? String == "committed", failure == "encode" {
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
            return try MCPWriteOutcome.encode(envelope)
        }, recovery: {
            if failure == "uncertain" { throw TaskLinkCommitDiskFixture.Failure.injected }
        })
        let policy = MCPBatchWritePolicy(afterTaskApply: { _, _, services in
            try fixture.stageGraph(context: services.context, insertedID: insertedID, evidenceID: evidenceID)
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == (failure == "uncertain" ? "uncertain" : "rejected"))
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id == fixture.edge.id)
        #expect(edges.first?.kindRawValue == "dependency")
        #expect(edges.first?.sourceTaskID == fixture.target.id)
        #expect(edges.first?.targetTaskID == fixture.source.id)
        #expect(edges.first?.createdAt == fixture.instant)
        let evidence = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(!evidence.contains { $0.id == evidenceID })
        #expect(evidence.count == 1)
        #expect(evidence.first?.kindRawValue == "future-kind")
        #expect(evidence.first?.occurrenceRevision == "raw-imported-revision")
        #expect(evidence.first?.sourceTaskID == fixture.source.id)
        #expect(evidence.first?.targetTaskID == fixture.target.id)
        #expect(evidence.first?.createdAt == fixture.instant)
        #expect(evidence.first?.removedAt == fixture.instant)
        let receipt = try #require(try fixture.receipts(in: observer.context).first)
        #expect(receipt.stateRawValue == (failure == "uncertain" ? "accepted" : "rejected"))
        let historic = try fixture.historicReceipt(in: observer.context)
        #expect(historic.resultJSON == fixture.historicJSON)
        #expect(historic.requestJSON == fixture.historicRequest)
        #expect(historic.acceptedAt == fixture.instant && historic.completedAt == fixture.instant)
        #expect(historic.resultIsError == false && historic.stateRawValue == "committed")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["T1734_OUTSIDE_WRITER_OBSERVATIONS"] == "1"),
          arguments: ["endpoint", "cycle"])
    // This single control retains both the outside-writer interleaving and original byte replay assertions.
    // swiftlint:disable:next function_body_length
    func outsideWriterAfterValidationRemainsSavedAndRetainedReplayIsUnchanged(race: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        let peer = try fixture.observer()
        let insertedID = UUID(), evidenceID = UUID()
        var validated = false
        let policy = MCPBatchWritePolicy(afterTaskApply: { _, _, services in
            try fixture.stageGraph(context: services.context, insertedID: insertedID, evidenceID: evidenceID)
        }, validateBeforeApply: { _, _ in
            let fresh = try fixture.observer()
            let target = try fixture.task(fixture.target.id, in: fresh.context)
            guard target.statusRawValue == "done" else { throw MCPWriteFailure("GRAPH_CONFLICT", "Endpoint changed") }
            let dependencies = try fresh.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
                .filter { $0.kindRawValue == "dependency" && $0.id != fixture.edge.id }
            guard !fixture.hasCycle(dependencies) else { throw MCPWriteFailure("GRAPH_CONFLICT", "Dependency cycle") }
            validated = true
        })
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage {
                if race == "endpoint" {
                    let target = try fixture.task(fixture.target.id, in: peer.context)
                    target.statusRawValue = "abandoned"
                } else {
                    peer.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency",
                        sourceTaskID: fixture.source.id, targetTaskID: fixture.target.id, createdAt: fixture.instant))
                    peer.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency",
                        sourceTaskID: fixture.target.id, targetTaskID: fixture.source.id, createdAt: fixture.instant))
                }
                try peer.context.save()
            }
            try context.save()
        })
        let result = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(validated)
        #expect(try fixture.decode(result)["outcome"] as? String == "committed")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "committed update")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.filter { $0.id == insertedID }.count == 1 && !edges.contains { $0.id == fixture.edge.id })
        let removals = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(removals.filter { $0.id == evidenceID }.count == 1)
        if race == "endpoint" {
            // Abandoned is a valid status, not proof of a historical race fault.
            // Actual blocker assessment is tested after projection exists.
            #expect(try fixture.task(fixture.target.id, in: observer.context).statusRawValue == "abandoned")
        } else {
            #expect(fixture.hasCycle(edges.filter { $0.kindRawValue == "dependency" }))
            // Actual cycle diagnostics belong to tasks 5/6 and 21/22.
        }
        let savedReceipts = try fixture.receipts(in: observer.context)
        let receipt = try #require(savedReceipts.count == 1 ? savedReceipts.first : nil)
        #expect(receipt.stateRawValue == "committed")
        #expect(receipt.resultJSON == result.content.first?.text)
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(replay.content.first?.text == result.content.first?.text)
    }

    private func bindingBytes(_ fixture: TaskLinkCommitDiskFixture) throws -> [String: Data] {
        let root = fixture.directory.appendingPathComponent("guards/guards")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: files.filter { $0.pathExtension == "json" }.map {
            ($0.lastPathComponent, try Data(contentsOf: $0))
        })
    }
}
#endif
