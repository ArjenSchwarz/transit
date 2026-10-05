#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkOwnedScopeTests {
    @Test func sealedScopeAppliesAndSavesGraphDomainAndReceiptTogether() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let inserted = UUID(), removed = UUID()
        var validatedContext: ModelContext?
        var savedContext: ModelContext?
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices, afterTaskApply: { _, _, services in
            try fixture.stageGraph(context: services.context, insertedID: inserted, evidenceID: removed)
        }, validateBeforeApply: { _, context in
            #expect(context !== fixture.owner.context && !context.autosaveEnabled && !context.hasChanges)
            validatedContext = context
        })
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage { savedContext = context }
            try context.save()
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "committed")
        #expect(savedContext === validatedContext && savedContext !== fixture.owner.context)
        #expect(!fixture.owner.context.hasChanges)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "committed update")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id == inserted)
        let removals = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(removals.filter { $0.id == removed }.count == 1)
        let receipts = try fixture.receipts(in: observer.context)
        #expect(receipts.count == 1 && receipts.first?.stateRawValue == "committed")
        #expect(receipts.first?.resultJSON == result.content.first?.text)
    }

    @Test(arguments: ["save", "encode", "recovery"])
    func scopedFailureRollsBackOnlyOwnedGraphAndRetainsOutcomeEvidence(failure: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let inserted = UUID(), removed = UUID()
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices, afterTaskApply: { _, _, services in
            try fixture.stageGraph(context: services.context, insertedID: inserted, evidenceID: removed)
        })
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage, failure != "encode" { throw TaskLinkCommitDiskFixture.Failure.injected }
            try context.save()
        }, encode: { envelope in
            if failure == "encode", envelope["outcome"] as? String == "committed" {
                throw TaskLinkCommitDiskFixture.Failure.injected
            }
            return try MCPWriteOutcome.encode(envelope)
        }, recovery: {
            if failure == "recovery" { throw TaskLinkCommitDiskFixture.Failure.injected }
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == (failure == "recovery" ? "uncertain" : "rejected"))
        #expect(!fixture.owner.context.hasChanges)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(edges.count == 1 && edges.first?.id == fixture.edge.id)
        let evidence = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(evidence.count == 1 && !evidence.contains { $0.id == removed })
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
        let receipts = try fixture.receipts(in: observer.context)
        #expect(receipts.count == 1)
        #expect(receipts.first?.stateRawValue == (failure == "recovery" ? "accepted" : "rejected"))
    }

    @Test(arguments: ["throw", "mismatch", "dirty", "shared-draft"])
    func invalidFactoryStopsWithoutSavingOrRollingBackSharedDrafts(fault: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        var terminalSaves = 0
        let policy = MCPBatchWritePolicy(makeCommitServices: { context in
            switch fault {
            case "throw": throw TaskLinkCommitDiskFixture.Failure.injected
            case "mismatch": return fixture.commitServices(in: fixture.owner.context)
            case "dirty":
                context.insert(Project(name: "owned pending", description: "", gitRepo: nil, colorHex: "112233"))
            case "shared-draft": fixture.source.name = "UI draft from callback"
            default: break
            }
            return fixture.commitServices(in: context)
        })
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage { terminalSaves += 1 }
            if case .rejection = stage { terminalSaves += 1 }
            try context.save()
        })
        let result = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "uncertain")
        #expect(terminalSaves == 0)
        #expect(fixture.owner.context.hasChanges == (fault == "shared-draft"))
        if fault == "shared-draft" { #expect(fixture.source.name == "UI draft from callback") }
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "accepted")
    }

    @Test(arguments: ["id", "payload", "format", "scope", "tool"])
    func refetchedReceiptMustMatchEntireOriginalAcceptanceBinding(field: String) async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices)
        var commitSaves = 0
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage { commitSaves += 1 }
            try context.save()
        }, preparation: { _ in
            let matches = try fixture.receipts(in: fixture.owner.context)
            let receipt = try #require(matches.count == 1 ? matches.first : nil)
            switch field {
            case "id": receipt.id = UUID()
            case "payload": receipt.requestJSON = "{\"changed\":true}"
            case "format": receipt.formatVersion = 2
            case "scope": receipt.localScopeID = "foreign-scope"
            case "tool": receipt.tool = "add_comment"
            default: break
            }
            try fixture.owner.context.save()
        })
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "uncertain")
        #expect(commitSaves == 0)
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "accepted")
    }

    @Test func dirtyReplayNeverConstructsOwnedScopeOrTouchesDrafts() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        var factories = 0, saves = 0
        let policy = MCPBatchWritePolicy(makeCommitServices: { context in
            factories += 1
            return fixture.commitServices(in: context)
        })
        let coordinator = fixture.coordinator(save: { context, _ in saves += 1; try context.save() })
        let first = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(try fixture.decode(first)["outcome"] as? String == "committed")
        let savedCount = saves
        fixture.source.name = "pending draft"
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(replay.content.first?.text == first.content.first?.text)
        #expect(factories == 1 && saves == savedCount)
        #expect(fixture.source.name == "pending draft" && fixture.owner.context.hasChanges)
    }

    @Test func preparationErrorUsesOwnedRejectionScopeAndOriginalKeyReplay() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        var rejectionWasOwned = false
        let policy = MCPBatchWritePolicy(makeCommitServices: fixture.commitServices)
        let coordinator = fixture.coordinator(save: { context, stage in
            if case .rejection = stage { rejectionWasOwned = context !== fixture.owner.context }
            try context.save()
        }, preparation: { _ in throw TaskLinkCommitDiskFixture.Failure.injected })
        let result = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        #expect(rejectionWasOwned && !fixture.owner.context.hasChanges)
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(replay.content.first?.text == result.content.first?.text)
    }
}
#endif
