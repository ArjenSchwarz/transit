#if os(macOS)
import Foundation
import SwiftData
import HTTPTypes
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskModernTests {
    private typealias Fixture = MCPBatchTaskModernFixture
    private typealias JSON = MCPBatchTaskResultFixtures

    @Test func registeredToolPublishesRichSchemaAndBatchClassification() throws {
        let definitions = try MCPToolDefinitions.modernTools(includingMaintenance: false)
        let descriptor = try #require(definitions.first { $0.name == "mutate_tasks" })
        let properties = JSON.field("properties", in: descriptor.inputSchema.value)
        let items = JSON.field("items", in: properties)
        #expect(JSON.field("minItems", in: items) != nil && JSON.field("maxItems", in: items) != nil)
        #expect(JSON.field("oneOf", in: JSON.field("items", in: items)) != nil)
        #expect(JSON.field("batchPayload", in:
            JSON.field("$defs", in: descriptor.resultSchema.outputSchema.value)) != nil)
        let availability = MCPModernProviderBinding.availability(maintenanceEnabled: false)
        let tool = try #require(availability.tools.first { $0.name == "mutate_tasks" })
        guard case .applicationBatch = tool.execution else {
            Issue.record("Expected application batch execution"); return
        }
        #expect(!MCPWriteCommand.protectedTools.contains("mutate_tasks"))
        #expect(!MCPWriteCommand.revisionTools.contains("mutate_tasks"))
        #expect(MCPBoundedReadDispatcher.classify(
            MCPTestHelpers.toolCallRequest(tool: "mutate_tasks", arguments: [:])) == nil)
        #expect(definitions.map(\.name) == MCPToolDefinitions.coreTools.map(\.name))
    }

    @Test func realPreviewThenCanonicalConsolidationAndReplay() async throws {
        let fixture = try Fixture()
        let domain = fixture.domain
        let items = try [domain.item(0, changes: ["description": " Combined rationale "]),
            domain.item(1, operation: "update_task_status", changes: ["comment": "Duplicate one"]),
            domain.item(2, operation: "update_task_status", changes: ["comment": "Duplicate two"])]
        let preview = try Fixture.payload(await fixture.call(mode: "dry_run", items: items))
        #expect(JSON.field("summary", in: preview) == .string("preview_valid"))
        #expect(domain.saveStages.isEmpty && domain.owner.context.hasChanges == false)
        let response = try await fixture.call(mode: "execute", items: items)
        let execution = try Fixture.payload(response)
        #expect(JSON.field("summary", in: execution) == .string("all_committed"))
        #expect(try domain.durableTasks().first { $0.id == domain.tasks[0].id }?.taskDescription ==
            "Combined rationale")
        #expect(try domain.durableComments().map(\.content).sorted() == ["Duplicate one", "Duplicate two"])
        let replay = try await fixture.call(mode: "execute", items: items, id: "replay.rpc")
        #expect(try Fixture.payload(replay) == execution)
        #expect(try domain.durableComments().count == 2)
        let request = try domain.request(items)
        guard case .array(let mapped) = JSON.field("items", in: execution) else {
            Issue.record("Expected original item evidence"); return
        }
        for item in request.items {
            let historic = try await domain.source(item, batchPolicy: nil)
            let original = JSON.field("originalResult", in: mapped[item.index])
            let rawText = try #require(MCPBatchTaskInputValue.string(JSON.field("text", in: original)))
            #expect(rawText.utf8.elementsEqual(historic.originalText.utf8))
            #expect(JSON.field("isError", in: original) == historic.originalIsError.map(MCPJSONValue.boolean))
            let bytes = try #require(historic.document?.originalUTF8)
            #expect(response.body.range(of: bytes) != nil)
        }
        let result = JSON.field("result", in: try MCPJSONDocument.parse(response.body).value)
        let links = JSON.field("links", in: JSON.field("presentation", in: JSON.field("structuredContent", in: result)))
        guard case .array(let values) = links else { Issue.record("Expected task navigation links"); return }
        #expect(values.count == 3)
        #expect(JSON.field("sourcePath", in: values[0]) == .string("/items/0/taskId"))
    }

    @Test func domainStopAndCorrectedFreshKeyResumePreservePrefix() async throws {
        let fixture = try Fixture()
        let first = try fixture.domain.item(0)
        let invalid = try fixture.domain.item(1, changes: ["priority": "invalid-domain-priority"])
        let items = try [first, invalid, fixture.domain.item(2)]
        let stopped = try Fixture.payload(await fixture.call(mode: "execute", items: items))
        #expect(JSON.field("summary", in: stopped) == .string("stopped"))
        guard case .array(let mapped) = JSON.field("items", in: stopped) else {
            Issue.record("Expected mapped outcomes"); return
        }
        #expect(JSON.field("state", in: mapped[2]) == .string("not_attempted"))
        let fixed = try fixture.domain.item(1, changes: ["priority": "high", "idempotencyKey": "corrected.fresh.key"])
        let resumed = try Fixture.payload(await fixture.call(mode: "execute", items: [first, fixed, items[2]]))
        #expect(JSON.field("summary", in: resumed) == .string("all_committed"))
    }

    @Test(arguments: [false, true])
    func previewRemainsAvailableWithoutWriteCoordinator(fallback: Bool) async throws {
        let fixture = try Fixture(fallback: fallback, missingCoordinator: true)
        let item = try fixture.domain.item(0)
        let preview = try Fixture.payload(await fixture.call(mode: "dry_run", items: [item]))
        #expect(JSON.field("summary", in: preview) == .string(fallback ? "preview_invalid" : "preview_valid"))
        let execute = try Fixture.payload(await fixture.call(mode: "execute", items: [item]))
        #expect(JSON.field("summary", in: execute) == .string("stopped"))
        #expect(fixture.domain.saveStages.isEmpty)
    }

    @Test func notificationShapeNeverExecutesOrFabricatesAResponseID() async throws {
        let fixture = try Fixture()
        let item = try fixture.domain.item(0)
        let object: [String: Any] = ["jsonrpc": "2.0", "method": "tools/call", "params": [
            "_meta": MCPModernResultFixture.meta, "name": "mutate_tasks",
            "arguments": ["mode": "execute", "items": [item]]]]
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let response = try await fixture.raw(try #require(String(data: bytes, encoding: .utf8)))
        #expect(response.status == .badRequest && response.body.isEmpty)
        #expect(fixture.domain.saveStages.isEmpty)
    }

    @Test func exactRawFractionalIntegerRejectsBeforeAnyEffects() async throws {
        let fixture = try Fixture()
        let item = try fixture.domain.item(0, changes: ["milestoneDisplayId": 1])
        let body = try MCPModernResultFixture.body(method: "tools/call", parameters: ["name": "mutate_tasks",
            "arguments": ["mode": "execute", "items": [item]]])
        let mutated = body.replacingOccurrences(of: "\"milestoneDisplayId\":1", with:
            "\"milestoneDisplayId\":1.000000000000000000000000000000000000001")
        #expect(mutated != body)
        let payload = try Fixture.payload(await fixture.raw(mutated))
        #expect(JSON.field("summary", in: payload) == .string("rejected_input"))
        #expect(fixture.domain.saveStages.isEmpty)
    }

    @Test func actualRouteEncodingFailureAfterCommitReturnsCorrelatedCompactFallback() async throws {
        let fixture = try Fixture(encoder: { _, _, _ in throw MCPResultBoundaryError.resourceLimit })
        var item = try fixture.domain.item(0, operation: "add_comment")
        let giant = String(repeating: "giant-caller-label", count: 10_000)
        item["itemId"] = giant
        let response = try await fixture.call(mode: "execute", items: [item], id: "fault.rpc")
        let payload = try Fixture.payload(response)
        #expect(JSON.field("summary", in: payload) == .string("serialization_failed"))
        let wire = try #require(String(data: response.body, encoding: .utf8))
        #expect(!wire.contains(giant))
        #expect(JSON.field("id", in: try MCPJSONDocument.parse(response.body).value) == .string("fault.rpc"))
        #expect(try fixture.domain.durableComments().count == 1)
        let request = try fixture.domain.request([item])
        let replay = try await fixture.domain.source(request.items[0])
        #expect(replay.originalIsError == nil)
        #expect(try fixture.domain.durableComments().count == 1)
    }
}
#endif
