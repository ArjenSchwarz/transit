#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Participating-operation controls; no exclusion of independent writers.
@MainActor @Suite(.serialized)
struct TaskLinkParticipatingBoundaryTests {
    @Test func existingPolicyMustRejectChangedSavedRevisionDespiteRegisteredSource() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        let oldRevision = try #require(arguments["expectedRevision"] as? String)
        let peer = try fixture.observer()
        var changedSavedRevision = false
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() }, preparation: { _ in
            let source = try fixture.task(fixture.source.id, in: peer.context)
            source.name = "outside saved update"
            try peer.context.save()
            let fresh = try fixture.observer()
            let savedSource = try fixture.task(fixture.source.id, in: fresh.context)
            changedSavedRevision = try MCPRecordSnapshot.task(savedSource, in: fresh.context).revision != oldRevision
        })
        // Genuine existing-SUT expectation: no custom fresh validator repairs
        // the long-lived policy/apply context. Runtime establishes RED/GREEN.
        let result = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: .init())
        #expect(changedSavedRevision)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "outside saved update")
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "rejected")
    }

    @Test func freshSavedEndpointRevisionRejectsChangeHiddenByRegisteredEndpoint() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let arguments = try fixture.updateArguments()
        let endpointRevision = try MCPRecordSnapshot.task(fixture.target, in: fixture.owner.context).revision
        let peer = try fixture.observer()
        var observedChangedEndpoint = false
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() }, preparation: { _ in
            let endpoint = try fixture.task(fixture.target.id, in: peer.context)
            endpoint.name = "changed saved endpoint label"
            try peer.context.save()
        })
        let policy = MCPBatchWritePolicy { _, _ in
            let fresh = try fixture.observer()
            let endpoint = try fixture.task(fixture.target.id, in: fresh.context)
            let snapshot = try MCPRecordSnapshot.task(endpoint, in: fresh.context)
            observedChangedEndpoint = snapshot.revision != endpointRevision
            guard snapshot.revision == endpointRevision else {
                throw MCPWriteFailure("REVISION_CONFLICT", "Endpoint changed", currentRecord: snapshot.record)
            }
        }
        let result = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(observedChangedEndpoint)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        #expect(try fixture.task(fixture.target.id, in: observer.context).name == "changed saved endpoint label")
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments, batchPolicy: policy)
        #expect(replay.content.first?.text == result.content.first?.text)
    }

    @Test func freshSavedCycleBeforeApplyRejectsAllOwnedEffects() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let peer = try fixture.observer()
        let proposedID = UUID(), removalID = UUID()
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() }, preparation: { _ in
            peer.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "dependency",
                sourceTaskID: fixture.source.id, targetTaskID: fixture.target.id, createdAt: fixture.instant))
            try peer.context.save()
        })
        let policy = MCPBatchWritePolicy { _, context in
            let fresh = try fixture.observer()
            let edges = try fresh.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
            guard !fixture.hasCycle(edges.filter { $0.kindRawValue == "dependency" }) else {
                throw MCPWriteFailure("GRAPH_CONFLICT", "Saved cycle before apply")
            }
            try fixture.stageGraph(context: context, insertedID: proposedID, evidenceID: removalID)
        }
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "rejected")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "source")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        #expect(fixture.hasCycle(edges) && !edges.contains { $0.id == proposedID })
        let removals = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        #expect(!removals.contains { $0.id == removalID })
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "rejected")
    }

    @Test func ownedGraphDomainAndTerminalReceiptCommitTogether() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let insertedID = UUID(), evidenceID = UUID()
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() })
        let policy = MCPBatchWritePolicy { _, context in
            try fixture.stageGraph(context: context, insertedID: insertedID, evidenceID: evidenceID)
        }
        let result = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                               batchPolicy: policy)
        #expect(try fixture.decode(result)["outcome"] as? String == "committed")
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "committed update")
        let edges = try observer.context.fetch(FetchDescriptor<TaskLinkOccurrence>())
        let edge = try #require(edges.count == 1 ? edges.first : nil)
        #expect(edge.id == insertedID && edge.kindRawValue == "association")
        #expect(edge.sourceTaskID == fixture.source.id && edge.targetTaskID == fixture.target.id)
        #expect(edge.createdAt == fixture.instant)
        let removals = try observer.context.fetch(FetchDescriptor<TaskLinkRemovalEvidence>())
        let matching = removals.filter { $0.id == evidenceID }
        let removal = try #require(matching.count == 1 ? matching.first : nil)
        #expect(removal.edgeId == fixture.edge.id && removal.kindRawValue == "dependency")
        #expect(removal.sourceTaskID == fixture.target.id && removal.targetTaskID == fixture.source.id)
        #expect(removal.createdAt == fixture.instant && removal.removedAt == fixture.instant)
        #expect(removal.occurrenceRevision == "l1:" + String(repeating: "0", count: 64))
        let savedReceipts = try fixture.receipts(in: observer.context)
        let receipt = try #require(savedReceipts.count == 1 ? savedReceipts.first : nil)
        #expect(receipt.stateRawValue == "committed" && receipt.resultIsError == false)
        #expect(receipt.resultJSON == result.content.first?.text)
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
    }

    @Test func participatingOperationCannotEnterDuringSynchronousFinalPhase() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        var events: [String] = []
        var queued: Task<Bool, Error>?
        var coordinator: MCPWriteCoordinator!
        var commitNumber = 0
        let policy = MCPBatchWritePolicy { command, _ in
            let first = command.key == "boundary-update"
            events.append(first ? "first.validate" : "peer.validate")
            if first {
                queued = Task { @MainActor in
                    events.append("peer.enter")
                    var arguments = try fixture.updateArguments()
                    arguments["idempotencyKey"] = "participating-peer"
                    arguments["name"] = "peer update"
                    let result = await coordinator.execute(tool: "update_task", arguments: arguments,
                                                           batchPolicy: .init())
                    return try fixture.decode(result)["outcome"] as? String == "committed"
                }
            }
        }
        coordinator = fixture.coordinator(save: { context, stage in
            if case .commit = stage {
                commitNumber += 1
                let prefix = commitNumber == 1 ? "first" : "peer"
                events.append(prefix + ".save.begin")
                try context.save()
                events.append(prefix + ".save.end")
            } else { try context.save() }
        }, encode: { envelope in
            if envelope["outcome"] as? String == "committed" {
                let prefix = envelope["idempotencyKey"] as? String == "boundary-update" ? "first" : "peer"
                events.append(prefix + ".encode")
            }
            return try MCPWriteOutcome.encode(envelope)
        })
        let first = await coordinator.execute(tool: "update_task", arguments: try fixture.updateArguments(),
                                              batchPolicy: policy)
        #expect(try fixture.decode(first)["outcome"] as? String == "committed")
        let peerTask = try #require(queued)
        let peerCommitted = try await peerTask.value
        #expect(peerCommitted)
        #expect(events == ["first.validate", "first.encode", "first.save.begin", "first.save.end",
                           "peer.enter", "peer.encode", "peer.save.begin", "peer.save.end"])
        let observer = try fixture.observer()
        #expect(try fixture.task(fixture.source.id, in: observer.context).name == "peer update")
        #expect(try fixture.receipts(in: observer.context).first?.stateRawValue == "committed")
        let key = "participating-peer"
        let peerReceipts = try observer.context.fetch(FetchDescriptor<MCPWriteReceipt>(
            predicate: #Predicate { $0.key == key }))
        #expect(peerReceipts.count == 1 && peerReceipts.first?.stateRawValue == "committed")
        // This exercises participating MainActor jobs only, not outside imports.
    }

}

@MainActor
extension TaskLinkCommitDiskFixture {
    func receipts(in context: ModelContext) throws -> [MCPWriteReceipt] {
        let key = "boundary-update"
        return try context.fetch(FetchDescriptor<MCPWriteReceipt>(predicate: #Predicate { $0.key == key }))
    }

    /// Reads the complete saved dependency predicate for this small fixture,
    /// after its proposed removal. Associations do not contribute cycle edges.
    func hasCycle(_ edges: [TaskLinkOccurrence]) -> Bool {
        var visiting = Set<UUID>(), visited = Set<UUID>()
        let adjacency = Dictionary(grouping: edges, by: \.sourceTaskID)
        func visit(_ id: UUID) -> Bool {
            if visiting.contains(id) { return true }
            if visited.contains(id) { return false }
            visiting.insert(id)
            for edge in adjacency[id] ?? [] where visit(edge.targetTaskID) { return true }
            visiting.remove(id)
            visited.insert(id)
            return false
        }
        return adjacency.keys.contains { visit($0) }
    }

    func stageGraph(context: ModelContext,
                    insertedID: UUID, evidenceID: UUID) throws {
        let edgeID = edge.id
        var descriptor = FetchDescriptor<TaskLinkOccurrence>(predicate: #Predicate { $0.id == edgeID })
        descriptor.fetchLimit = 2
        let matches = try context.fetch(descriptor)
        let savedEdge = try #require(matches.count == 1 ? matches.first : nil)
        context.delete(savedEdge)
        context.insert(TaskLinkOccurrence(id: insertedID, kindRawValue: "association",
            sourceTaskID: source.id, targetTaskID: target.id, createdAt: instant))
        context.insert(TaskLinkRemovalEvidence(id: evidenceID, edgeId: edge.id, kindRawValue: "dependency",
            sourceTaskID: target.id, targetTaskID: source.id, createdAt: instant,
            occurrenceRevision: "l1:" + String(repeating: "0", count: 64), removedAt: instant))
    }
}
#endif
