#if os(macOS)
import Foundation
import HTTPTypes
import Testing
@testable import Transit
@MainActor @Suite(.serialized) struct TaskConsolidationWireResultTests {
    @Test func modernSourceReferencesAndOriginalKeyReplayKeepSavedBytes() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let preview = try await workflow.read("preview_task_consolidation", workflow.fixture.arguments)
        let command: [String: Any] = ["idempotencyKey": "wire-apply", "preservationAcknowledged": true,
            "reviewId": try #require(preview["reviewId"]), "reviewRevision": try #require(preview["reviewRevision"])]
        let response = try await call(workflow.handler, tool: "consolidate_tasks", arguments: command)
        #expect(response.status == .ok)
        let result = try MCPModernResultFixture.assertSource(response, id: .integer(1))
        let structured = try MCPResultEncoderFixtures.structured(result)
        let presentation = try #require(MCPResultEncoderFixtures.field("presentation", in: structured))
        let links = try #require(MCPResultEncoderFixtures.field("links", in: presentation))
        guard case .array(let values) = links else { Issue.record("Missing current task positions"); return }
        let ids = values.compactMap { MCPResultInspection.string(MCPResultEncoderFixtures.field("entityId", in: $0)) }
        let operation = try #require(try workflow.fixture.capture().events.first?.operationId)
        #expect(!ids.contains(operation.uuidString))
        for id in [workflow.fixture.base.base.source.id, workflow.fixture.base.base.target.id,
            workflow.fixture.base.extra.id] {
            #expect(ids.contains(id.uuidString))
        }
        workflow.fixture.store.clear()
        let replay = try await call(workflow.handler, tool: "consolidate_tasks", arguments: command)
        #expect(replay.body == response.body && workflow.fixture.base.observation.commitSaves == 1)
    }
    @Test func postCommitWrapperFaultSelectsCompactOriginalKeyRecovery() async throws {
        let workflow = try ConsolidationAppWorkflowFixture(resultEncoder: { _, _, _ in throw WireFault.encoding })
        let preview = try await workflow.read("preview_task_consolidation", workflow.fixture.arguments)
        let response = try await call(workflow.handler, tool: "consolidate_tasks", arguments: [
            "idempotencyKey": "wire-fault", "preservationAcknowledged": true,
            "reviewId": try #require(preview["reviewId"]), "reviewRevision": try #require(preview["reviewRevision"])])
        let result = try MCPModernResultFixture.assertSource(response, id: .integer(1))
        let text = try MCPResultEncoderFixtures.originalText(result)
        #expect(text.contains("OUTCOME_UNCERTAIN"))
        #expect(response.body.count < 4_096)
        let body = try #require(String(data: response.body, encoding: .utf8))
        #expect(body.contains("wire-fault") && body.contains("consolidate_tasks"))
        #expect(try workflow.fixture.capture().events.count == 1)
        #expect(workflow.fixture.base.observation.commitSaves == 1)
    }
    @Test func uncertainUndoRetainsKnownOperationIdentity() async throws {
        let workflow = try ConsolidationAppWorkflowFixture(resultEncoder: { _, _, _ in throw WireFault.encoding })
        let preview = try await workflow.read("preview_task_consolidation", workflow.fixture.arguments)
        let applied = try await workflow.write("consolidate_tasks", [
            "idempotencyKey": "before-wire-undo", "preservationAcknowledged": true,
            "reviewId": try #require(preview["reviewId"]), "reviewRevision": try #require(preview["reviewRevision"])])
        let operation = try #require(applied["operationId"] as? String)
        let inverse = try await workflow.read("preview_task_consolidation_undo", ["operationId": operation])
        let response = try await call(workflow.handler, tool: "undo_task_consolidation", arguments: [
            "idempotencyKey": "wire-undo-fault", "operationId": operation,
            "reviewId": try #require(inverse["reviewId"]), "reviewRevision": try #require(inverse["reviewRevision"])])
        let result = try MCPModernResultFixture.assertSource(response, id: .integer(1))
        let text = try MCPResultEncoderFixtures.originalText(result)
        #expect(text.contains("OUTCOME_UNCERTAIN") && text.contains(operation))
        let body = try #require(String(data: response.body, encoding: .utf8))
        #expect(body.contains("wire-undo-fault") && body.contains("undo_task_consolidation"))
        #expect(response.body.count < 4_096)
        #expect(try workflow.fixture.capture().events.count == 2)
        #expect(workflow.fixture.base.observation.commitSaves == 2)
    }

    private func call(_ handler: MCPToolHandler, tool: String, arguments: [String: Any]) async throws
        -> MCPHTTPTestResponse {
        try await MCPModernResultFixture.transport(handler: handler, contentType: "application/json",
            accept: "application/json, text/event-stream", protocolVersion: "2026-07-28", orderedHeaders: [
                HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call"),
                HTTPField(name: HTTPField.Name("Mcp-Name")!, value: tool)
            ], body: MCPModernResultFixture.body(method: "tools/call", parameters: ["name": tool,
                "arguments": arguments]),
            loggerLabel: "t2381-consolidation-wire")
    }
    private enum WireFault: Error { case encoding }
}
#endif
