#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Real protected routes and independently opened saved observers. Closed-store
/// upgrade itself is covered by the separately drained migration-stage runner.
@MainActor @Suite(.serialized)
struct TaskLinkFoundationIntegrationTests {
    @Test func protectedRepairKeepsFrozenQueryWhileNativeSeesSavedIncidence() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let writes = TaskLinkWriteFixture(base: base)
        let frozen = try capture(base)
        let before = try rows(frozen, id: base.source.id)
        let args = try writes.removal(key: "integration-repair")
        let result = await writes.execute(args)
        try writes.assertOutcome(result, "committed")
        base.source.name = "UI draft after repair"
        let native = try TaskLinkService(container: base.owner.container).savedDetail(for: base.source.id)
        #expect(native.source.name == "source")
        #expect(native.graph.incidence[base.source.id, default: []].isEmpty)
        let current = try rows(capture(base), id: base.source.id)
        #expect(current[0]["revision"] as? String != before[0]["revision"] as? String)
        #expect(try canonical(rows(frozen, id: base.source.id)) == canonical(before))
        #expect(frozen.taskLinkGraph?.occurrences.map(\.id) == [base.edge.id])
        let replay = await writes.execute(args)
        #expect(replay.content.first?.text == result.content.first?.text)
        let observer = try base.observer()
        let destination = try TaskLinkNavigationResolver.resolve(base.target.id, in: observer.context)
        #expect(destination?.id == base.target.id)
        #expect(try base.historicReceipt(in: observer.context).resultJSON == base.historicJSON)
        #expect(base.owner.context.hasChanges)
    }

    @Test func creationStatusCommentAndParticipatingBatchKeepPortfolioCounts() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let writes = TaskLinkWriteFixture(base: base)
        let creation = try creationArguments(base, writes: writes)
        let created = await writes.execute(creation, tool: "create_task")
        try writes.assertOutcome(created, "committed")
        let record = try #require(try base.decode(created)["record"] as? [String: Any])
        let id = try #require((record["taskId"] as? String).flatMap(UUID.init(uuidString:)))
        let status: [String: Any] = ["taskId": id.uuidString, "expectedRevision": try writes.revision(id),
            "idempotencyKey": "integration-status", "status": "in-progress", "comment": " reason ",
            "authorName": " Agent "]
        try writes.assertOutcome(await writes.execute(status, tool: "update_task_status"), "committed")
        let batchArgs: [String: Any] = ["taskId": id.uuidString, "expectedRevision": try writes.revision(id),
            "idempotencyKey": "integration-batch", "name": " Batch name "]
        let document = try MCPBatchTaskRequestFixtures.document(items: [
            ["itemId": "owned", "operation": "update_task", "arguments": batchArgs]])
        let request = try MCPBatchTaskRequestFixtures.valid(document)
        let execution = try await writes.handler.executeBatchItem(request.items[0])
        #expect(!execution.pendingEditsStop)
        let observer = try base.observer()
        let task = try base.task(id, in: observer.context)
        #expect(task.name == "Batch name" && task.statusRawValue == "in-progress")
        let comments = try observer.context.fetch(CommentService.descriptor(for: id))
        #expect(comments.count == 1 && comments[0].content == "reason" && comments[0].authorName == "Agent")
        let view = try capture(base, portfolio: true)
        let summary = try PortfolioSummaryService.summarize(view: view,
            window: CompletionWindow(start: Date(timeIntervalSince1970: 0), end: Date()+60))
        #expect(summary.projects.first?.totalTaskCount == 3)
        #expect(view.tasks.count == 3 && view.taskLinkGraph?.tasks.count == 3)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 2)
        try assertBatchGraphShapeRejected(batchArgs, base: base)
        let replay = await writes.execute(creation, tool: "create_task")
        #expect(replay.content.first?.text == created.content.first?.text)
        #expect(try base.historicReceipt(in: observer.context).resultJSON == base.historicJSON)
    }

    @Test func maintenanceExpiryDoesNotRemintTerminalResultOrFrozenToken() async throws {
        let base = try TaskLinkCommitDiskFixture()
        let writes = TaskLinkWriteFixture(base: base)
        let args = try writes.removal(key: "integration-expiry")
        let result = await writes.execute(args)
        try writes.assertOutcome(result, "committed")
        let frozen = try capture(base)
        let original = try rows(frozen, id: base.source.id)
        let revision = try writes.revision(base.source.id)
        let instant = Date() + TaskLinkGraph.evidenceLifetime + 60
        #expect(try TaskLinkService(container: base.owner.container).cleanupExpiredEvidence(
            evaluationInstant: instant) == 1)
        #expect(try writes.revision(base.source.id) == revision)
        #expect(try canonical(rows(frozen, id: base.source.id)) == canonical(original))
        let replay = await writes.execute(args)
        #expect(replay.content.first?.text == result.content.first?.text)
        let observer = try base.observer()
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 0)
        #expect(try observer.context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()) == 1)
        #expect(try writes.receipts(for: args, in: observer.context).first?.resultJSON == result.content.first?.text)
        #expect(try base.historicReceipt(in: observer.context).resultJSON == base.historicJSON)
    }

    private func capture(_ base: TaskLinkCommitDiskFixture, portfolio: Bool = false) throws -> CapturedReadView {
        try MCPReadCaptureBuilder(container: base.owner.container, fence: .actorOnlyTestFixture).capture(
            ReadCaptureRequest(projectSelectors: nil, selection: portfolio ? .portfolio : .tasks(detail: .fullRecord),
                completeness: portfolio ? .completePortfolio : .selectedRead, includeComments: true))
    }

    private func rows(_ view: CapturedReadView, id: UUID) throws -> [[String: Any]] {
        let args: [String: Any] = ["detailLevel": "full", "includeComments": true, "limit": 100]
        return try MCPReadProjection.tasks(view, request: MCPTaskQueryRequest.parse(args), arguments: args)
            .filter { $0["taskId"] as? String == id.uuidString }
    }

    private func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func creationArguments(_ base: TaskLinkCommitDiskFixture,
                                   writes: TaskLinkWriteFixture) throws -> [String: Any] {
        let projectID = try #require(base.source.project?.id)
        return ["name": "Integrated creation", "type": "feature", "projectId": projectID.uuidString,
            "idempotencyKey": "integration-create", "linkChanges": [["action": "add", "type": "relates-to",
                "targetTaskId": base.target.id.uuidString]], "endpointPreconditions": [[
                    "taskId": base.target.id.uuidString, "expectedRevision": try writes.revision(base.target.id)]]]
    }

    private func assertBatchGraphShapeRejected(_ original: [String: Any], base: TaskLinkCommitDiskFixture) throws {
        var unsupported = original
        unsupported["idempotencyKey"] = "integration-unsupported"
        unsupported["linkChanges"] = [] as [[String: Any]]
        let document = try MCPBatchTaskRequestFixtures.document(items: [
            ["itemId": "unsupported", "operation": "update_task", "arguments": unsupported]])
        try MCPBatchTaskRequestFixtures.invalid(document, index: 0, field: "linkChanges")
        let key = "integration-unsupported"
        let receipts = try base.observer().context.fetch(FetchDescriptor<MCPWriteReceipt>(
            predicate: #Predicate { $0.key == key }))
        #expect(receipts.isEmpty)
    }
}
#endif
