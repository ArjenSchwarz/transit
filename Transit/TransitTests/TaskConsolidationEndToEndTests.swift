#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit
@MainActor @Suite(.serialized) struct TaskConsolidationEndToEndTests {
    @Test func sixTicketWorkflowPreservesExactOriginalsAndRetainedChains() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        try await advertisedTools(workflow)
        let seed = try seed(workflow)
        let unselected = try seedUnselected(workflow)
        let untouched = try capture(workflow, ids: unselected)
        let page = try await workflow.read("query_tasks", ["taskIds": seed.ids.map(\.uuidString),
            "detailLevel": "full", "includeComments": true, "limit": 1, "readPolicy": "cached"])
        let cursor = try #require(page["nextCursor"] as? String)
        let retainedPage = try await workflow.readText("query_tasks", ["cursor": cursor])
        let before = try capture(workflow, ids: seed.ids)
        let preview = try await workflow.read("preview_task_consolidation", seed.arguments)
        #expect((preview["originals"] as? [[String: Any]])?.count == 6)
        let apply = try await workflow.write("consolidate_tasks", reference(preview, key: "six-apply", apply: true))
        #expect(apply["outcome"] as? String == "committed")
        #expect((apply["mappings"] as? [[String: Any]])?.count == 6)
        let after = try capture(workflow, ids: seed.ids)
        let operation = try #require(after.events.first?.operationId)
        try await publicHistory(workflow, ids: seed.ids, operation: operation, reversed: false)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(untouched.originals,
            capture(workflow, ids: unselected).originals))
        try await retainedPageUnchanged(workflow, cursor: cursor, before: retainedPage)
        try historicalReceiptUnchanged(workflow)
        let history = try TaskConsolidationHistoryCodec.history(after.events, operationId: operation).apply
        #expect(history.retainedOccurrences.contains { $0.id == seed.chainId })
        #expect(history.candidateTaskIds.count == 5)
        try preservedCandidateContentAndTerminalDates(before: before, after: after, survivor: seed.ids[0])
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
        try await publicHistory(workflow, ids: seed.ids, operation: operation, reversed: true)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(untouched.originals,
            capture(workflow, ids: unselected).originals))
        let untouchedEdge = try #require(untouched.graph.occurrences.first { unselected.contains($0.source) })
        let currentEdge = try #require(capture(workflow, ids: unselected).graph.occurrences.first {
            $0.id == untouchedEdge.id
        })
        #expect(try TaskLinkGraph.occurrenceRevision(currentEdge)
            == TaskLinkGraph.occurrenceRevision(untouchedEdge))
        #expect(try JSONDecoder().decode(PersistentIdentifier.self, from: currentEdge.physicalKey)
            == JSONDecoder().decode(PersistentIdentifier.self, from: untouchedEdge.physicalKey))
        try await retainedPageUnchanged(workflow, cursor: cursor, before: retainedPage)
        try historicalReceiptUnchanged(workflow)
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
        let firstText = try await workflow.writeText("consolidate_tasks", command)
        let first = try #require(JSONSerialization.jsonObject(with: Data(firstText.utf8)) as? [String: Any])
        #expect(first["outcome"] as? String == "committed")
        workflow.fixture.store.clear()
        let replayText = try await workflow.writeText("consolidate_tasks", command)
        let replay = try #require(JSONSerialization.jsonObject(with: Data(replayText.utf8)) as? [String: Any])
        #expect(Data(firstText.utf8) == Data(replayText.utf8))
        #expect(try MCPCanonicalJSON.encode(first) == MCPCanonicalJSON.encode(replay))
        try historicalReceiptUnchanged(workflow)
        let after = try workflow.fixture.capture()
        for original in before.originals {
            #expect(after.originals.first { $0.id == original.id }?.fields == original.fields)
        }
        #expect(workflow.fixture.base.observation.commitSaves == 1)
    }
    @Test(arguments: ["stale", "pending-draft"])
    func composedRejectionsPreserveSavedOriginalsAndPendingDrafts(fault: String) async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let preview = try await workflow.read("preview_task_consolidation", workflow.fixture.arguments)
        let base = workflow.fixture.base.base
        if fault == "stale" {
            let owner = try base.observer()
            let task = try base.task(base.source.id, in: owner.context)
            task.taskDescription = "Saved after review"
            try owner.context.save()
        } else { base.source.taskDescription = "Unsaved UI draft" }
        let before = try workflow.fixture.capture()
        let query = try await workflow.read("query_tasks", ["taskIds": [base.source.id.uuidString],
            "detailLevel": "full", "includeComments": true, "limit": 5, "readPolicy": "cached"])
        let task = try #require((query["results"] as? [[String: Any]])?.first?["task"] as? [String: Any])
        #expect(task["description"] as? String != "Unsaved UI draft")
        let result = try await workflow.write("consolidate_tasks", reference(preview, key: fault, apply: true))
        #expect(result["outcome"] as? String == (fault == "stale" ? "rejected" : "uncertain"))
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals,
            workflow.fixture.capture().originals))
        #expect(try workflow.fixture.capture().events.isEmpty)
        #expect(workflow.fixture.base.observation.commitSaves == 0)
        if fault == "pending-draft" {
            #expect(base.owner.context.hasChanges && base.source.taskDescription == "Unsaved UI draft")
        }
    }

    @Test func composedOverLimitPreviewPublishesNoReviewOrDomainEffects() async throws {
        let fixture = try ConsolidationPreviewFixture(maxBytes: 1)
        let workflow = try ConsolidationAppWorkflowFixture(fixture: fixture)
        let before = try fixture.capture()
        let result = try await workflow.read("preview_task_consolidation", fixture.arguments)
        #expect((result["error"] as? [String: Any])?["code"] as? String == "QUERY_CAPACITY_EXCEEDED")
        #expect(result["reviewId"] == nil && fixture.store.retainedBytes == 0)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(before.originals, fixture.capture().originals))
        #expect(try fixture.capture().events.isEmpty && fixture.base.observation.commitSaves == 0)
    }

    private func preservedCandidateContentAndTerminalDates(before: ConsolidationSavedEvidence,
                                                           after: ConsolidationSavedEvidence, survivor: UUID) throws {
        for prior in before.originals {
            let current = try #require(after.originals.first { $0.id == prior.id })
            if ["done", "abandoned"].contains(prior.fields.statusRawValue) {
                #expect(current.fields.lastStatusChangeDate == prior.fields.lastStatusChangeDate)
                #expect(current.fields.completionDate == prior.fields.completionDate)
            }
            if prior.id != survivor {
                #expect(current.fields.description == prior.fields.description)
                #expect(current.fields.metadataJSON == prior.fields.metadataJSON)
            }
        }
    }

    private func retainedPageUnchanged(_ workflow: ConsolidationAppWorkflowFixture, cursor: String,
                                       before: String) async throws {
        let after = try await workflow.readText("query_tasks", ["cursor": cursor])
        #expect(Data(before.utf8) == Data(after.utf8))
        let beforeValue = try #require(JSONSerialization.jsonObject(with: Data(before.utf8)) as? [String: Any])
        let afterValue = try #require(JSONSerialization.jsonObject(with: Data(after.utf8)) as? [String: Any])
        #expect(try MCPCanonicalJSON.encode(beforeValue) == MCPCanonicalJSON.encode(afterValue))
    }

    private func historicalReceiptUnchanged(_ workflow: ConsolidationAppWorkflowFixture) throws {
        let base = workflow.fixture.base.base
        let observer = try base.observer()
        let json = try #require(base.historicReceipt(in: observer.context).resultJSON)
        #expect(Data(json.utf8) == Data(base.historicJSON.utf8))
    }

    private func advertisedTools(_ workflow: ConsolidationAppWorkflowFixture) async throws {
        let response = try #require(await workflow.handler.handle(MCPTestHelpers.request(method: "tools/list")))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response))
            as? [String: Any])
        let tools = try #require((object["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(Set(["preview_task_consolidation", "consolidate_tasks", "preview_task_consolidation_undo",
            "undo_task_consolidation"]).isSubset(of: Set(tools.compactMap { $0["name"] as? String })))
    }

    private func publicHistory(_ workflow: ConsolidationAppWorkflowFixture, ids: [UUID], operation: UUID,
                               reversed: Bool) async throws {
        let result = try await workflow.read("query_tasks", ["taskIds": ids.map(\.uuidString),
            "detailLevel": "full", "includeComments": true, "limit": 100, "readPolicy": "cached"])
        let rows = try #require(result["results"] as? [[String: Any]])
        #expect(rows.count == ids.count)
        for (id, row) in zip(ids, rows) {
            let task = try #require(row["task"] as? [String: Any])
            #expect(task["taskId"] as? String == id.uuidString)
            #expect(task["consolidationHistoryCoverage"] as? String == "complete")
            let history = try #require(task["consolidationHistory"] as? [[String: Any]])
            let entry = try #require(history.first { $0["operationId"] as? String == operation.uuidString })
            let apply = try #require(entry["apply"] as? [String: Any])
            #expect(apply["reason"] as? String == "reviewed work")
            #expect((apply["candidateTaskIds"] as? [String])?.count == 5)
            #expect((apply["preservationJSON"] as? String)?.contains("Description, metadata and comments") == true)
            #expect((entry["reversal"] is [String: Any]) == reversed)
            #expect(entry["undoUnavailableReason"] as? String == (reversed ? "already_reversed" : nil))
        }
    }

    private func seedUnselected(_ workflow: ConsolidationAppWorkflowFixture) throws -> [UUID] {
        let base = workflow.fixture.base.base, context = base.owner.context
        let project = try #require(base.source.project)
        let left = TransitTask(name: "Unselected left", description: "Untouched detail", type: .feature,
            project: project, displayID: .permanent(70))
        let right = TransitTask(name: "Unselected right", type: .feature, project: project,
            displayID: .permanent(71))
        context.insert(left)
        context.insert(right)
        context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "association", sourceTaskID: left.id,
            targetTaskID: right.id, createdAt: Date(timeIntervalSinceReferenceDate: 32)))
        try context.save()
        return [left.id, right.id]
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
