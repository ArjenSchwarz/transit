#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit
@MainActor @Suite(.serialized) struct TaskConsolidationEndToEndTests {
    @Test func sixTicketWorkflowPreservesExactOriginalsAndRetainedChains() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let seed = try seed(workflow)
        let before = try capture(workflow, ids: seed.ids)
        let preview = try await workflow.read("preview_task_consolidation", seed.arguments)
        #expect((preview["originals"] as? [[String: Any]])?.count == 6)
        let apply = try await workflow.write("consolidate_tasks", reference(preview, key: "six-apply", apply: true))
        #expect(apply["outcome"] as? String == "committed")
        #expect((apply["mappings"] as? [[String: Any]])?.count == 6)
        let after = try capture(workflow, ids: seed.ids)
        let operation = try #require(after.events.first?.operationId)
        let history = try TaskConsolidationHistoryCodec.history(after.events, operationId: operation).apply
        #expect(history.retainedOccurrences.contains { $0.id == seed.chainId })
        #expect(history.candidateTaskIds.count == 5)
        for prior in before.originals {
            let current = try #require(after.originals.first { $0.id == prior.id })
            if ["done", "abandoned"].contains(prior.fields.statusRawValue) {
                #expect(current.fields.lastStatusChangeDate == prior.fields.lastStatusChangeDate)
                #expect(current.fields.completionDate == prior.fields.completionDate)
            }
            if prior.id != seed.ids[0] {
                #expect(current.fields.description == prior.fields.description)
                #expect(current.fields.metadataJSON == prior.fields.metadataJSON)
            }
        }
        let inverse = try await workflow.read("preview_task_consolidation_undo", ["operationId": operation.uuidString,
            "readPolicy": "cached"])
        var undo = reference(inverse, key: "six-undo", apply: false)
        undo["operationId"] = operation.uuidString
        let reversed = try await workflow.write("undo_task_consolidation", undo)
        #expect(reversed["outcome"] as? String == "committed")
        let restored = try capture(workflow, ids: seed.ids)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, restored.originals))
        #expect(restored.graph.occurrences.contains { $0.id == seed.chainId })
        #expect(restored.events.count == 2 && workflow.fixture.base.observation.commitSaves == 2)
    }
    @Test func terminalNoEditGroupRetainsDatesAndRecordedBytesAfterLostResponse() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let context = workflow.fixture.base.base.owner.context
        for task in [workflow.fixture.base.base.source, workflow.fixture.base.extra] {
            task.statusRawValue = "done"
            task.completionDate = Date(timeIntervalSinceReferenceDate: 77)
        }
        try context.save()
        let before = try workflow.fixture.capture()
        let preview = try await workflow.read("preview_task_consolidation", workflow.fixture.arguments)
        let command = reference(preview, key: "terminal-replay", apply: true)
        let first = try await workflow.write("consolidate_tasks", command)
        #expect(first["outcome"] as? String == "committed")
        workflow.fixture.store.clear()
        let replay = try await workflow.write("consolidate_tasks", command)
        #expect(try MCPCanonicalJSON.encode(first) == MCPCanonicalJSON.encode(replay))
        let after = try workflow.fixture.capture()
        for original in before.originals {
            #expect(after.originals.first { $0.id == original.id }?.fields == original.fields)
        }
        #expect(workflow.fixture.base.observation.commitSaves == 1)
    }
    private func reference(_ preview: [String: Any], key: String, apply: Bool) -> [String: Any] {
        var value: [String: Any] = ["idempotencyKey": key, "reviewId": preview["reviewId"] ?? NSNull(),
            "reviewRevision": preview["reviewRevision"] ?? NSNull()]
        if apply { value["preservationAcknowledged"] = true }
        return value
    }
    private func capture(_ workflow: ConsolidationAppWorkflowFixture, ids: [UUID]) throws
        -> ConsolidationSavedEvidence {
        try TaskConsolidationSavedCapture(container: workflow.fixture.base.base.owner.container,
            fence: .actorOnlyTestFixture).capture(selectedTaskIds: ids)
    }
    private struct SixTicketSeed {
        let ids: [UUID]
        let chainId: UUID
        let arguments: [String: Any]
    }
    private func seed(_ workflow: ConsolidationAppWorkflowFixture) throws
        -> SixTicketSeed {
        let base = workflow.fixture.base, context = base.base.owner.context
        let project = try #require(base.base.source.project)
        let additions = ["done", "abandoned", "in-progress"].enumerated().map { offset, status in
            let task = TransitTask(name: "candidate-\(offset)", description: "conflicting-\(offset)", type: .feature,
                project: project, displayID: .permanent(offset + 4))
            task.statusRawValue = status == "in-progress" ? TaskStatus.inProgress.rawValue : status
            task.metadataJSON = "{ \"detail\" : \"value-\(offset)\" }"
            task.lastStatusChangeDate = Date(timeIntervalSinceReferenceDate: Double(offset + 41))
            if status != "in-progress" { task.completionDate = task.lastStatusChangeDate }
            context.insert(task)
            context.insert(Comment(content: "unique-\(offset)", authorName: "fixture", isAgent: true, task: task))
            return task
        }
        let chain = TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate", sourceTaskID: additions[0].id,
            targetTaskID: base.base.source.id, createdAt: Date(timeIntervalSinceReferenceDate: 31))
        context.insert(chain)
        context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate", sourceTaskID: base.base.source.id,
            targetTaskID: base.base.target.id, createdAt: Date(timeIntervalSinceReferenceDate: 30)))
        try context.save()
        let ids = [base.base.target.id, base.base.source.id, base.extra.id] + additions.map(\.id)
        var arguments = workflow.fixture.arguments
        arguments["candidateTaskIds"] = Array(ids.dropFirst()).map(\.uuidString)
        arguments["survivorEdits"] = ["description": "explicit combined description",
            "metadata": ["detail": "explicit"]]
        arguments["preservation"] = Dictionary(uniqueKeysWithValues: ids.dropFirst().map {
            ($0.uuidString, ["retainedExplanation": "Description, metadata and comments remain on this original"])
        })
        return SixTicketSeed(ids: ids, chainId: chain.id, arguments: arguments)
    }
}
#endif
