#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationDiagnosticTests {
    @Test(arguments: ["missing_task", "ambiguous_task", "missing_project", "wrong_project", "survivor_not_canonical"])
    func rejectedSelectionIdentifiesTheSavedOffender(reason: String) async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let fixture = workflow.fixture
        let owner = try fixture.base.base.observer()
        let context = owner.context
        let offender = reason == "survivor_not_canonical" ? fixture.base.base.target.id : fixture.base.extra.id
        let task = try fixture.base.base.task(offender, in: context)
        switch reason {
        case "missing_task": context.delete(task)
        case "ambiguous_task":
            let duplicate = TransitTask(name: "collision", type: .feature,
                project: try #require(task.project), displayID: .permanent(99))
            duplicate.id = offender
            context.insert(duplicate)
        case "missing_project": task.project = nil
        case "wrong_project":
            let project = Project(name: "Other", description: "", gitRepo: nil, colorHex: "red")
            context.insert(project)
            task.project = project
        default:
            context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "duplicate", sourceTaskID: offender,
                targetTaskID: fixture.base.extra.id, createdAt: Date(timeIntervalSinceReferenceDate: 100)))
        }
        try context.save()
        let result = try await workflow.read("preview_task_consolidation", fixture.arguments)
        let error = try #require(result["error"] as? [String: Any])
        #expect(error["code"] as? String == "CONSOLIDATION_SELECTION_INVALID")
        let diagnostics = try #require(error["diagnostics"] as? [[String: String]])
        #expect(diagnostics == [["taskId": offender.uuidString, "reason": reason]])
        #expect(fixture.base.observation.commitSaves == 0)
        #expect(try context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
    }

    @Test func unavailableReviewModernRecoveryPreservesEstablishedRejection() async throws {
        let workflow = try ConsolidationAppWorkflowFixture()
        let preview = try await workflow.read("preview_task_consolidation", workflow.fixture.arguments)
        workflow.fixture.store.clear()
        let tool = "consolidate_tasks"
        let response = try await MCPModernResultFixture.transport(handler: workflow.handler,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: "2026-07-28", orderedHeaders: [
                HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call"),
                HTTPField(name: HTTPField.Name("Mcp-Name")!, value: tool)
            ], body: MCPModernResultFixture.body(method: "tools/call", parameters: ["name": tool,
                "arguments": ["reviewId": try #require(preview["reviewId"]),
                    "reviewRevision": try #require(preview["reviewRevision"]),
                    "preservationAcknowledged": true, "idempotencyKey": "expired-review"]]),
            loggerLabel: "t2381-diagnostic-wire")
        let result = try MCPModernResultFixture.assertSource(response, id: .integer(1))
        let source = try MCPResultEncoderFixtures.originalText(result)
        #expect(source.contains("CONSOLIDATION_REVIEW_UNAVAILABLE") && source.contains("rejected")
            && source.contains("new_request_new_key"))
        let structured = try MCPResultEncoderFixtures.structured(result)
        let presentation = try #require(MCPResultEncoderFixtures.field("presentation", in: structured))
        let recovery = try #require(MCPResultEncoderFixtures.field("recovery", in: presentation))
        #expect(MCPResultEncoderFixtures.field("direction", in: recovery) == .string("follow_source"))
        #expect(workflow.fixture.base.observation.commitSaves == 0)
    }
}
#endif
