#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskAggregateTests {
    private typealias Sequence = MCPBatchTaskCoordinatorSequenceFixtures
    private typealias Fixture = MCPBatchTaskResultFixtures

    @Test(arguments: [nil, false, true] as [Bool?])
    func nestedOriginalValueTextAndOptionalFlagStayExact(flag: Bool?) async throws {
        let request = try Sequence.request(count: 1)
        let text = Fixture.committed(extra: #", "unknown":{"n":1E9999,"null":null,"source":"collision"}"#)
            .replacingOccurrences(of: Fixture.taskID.uuidString, with: request.items[0].targetTaskId.uuidString)
            .replacingOccurrences(of: Fixture.key, with: request.items[0].command.key)
        let original = try MCPResultAdapter.source(text: text, isError: flag,
                                                   origin: .retainedJSON, evidence: .established)
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request), executor: { _ in
            .init(source: original)
        })
        let report = try await batch.run(request)
        let source = try MCPBatchTaskResult.execution(request, report: report)
        #expect(Fixture.field("mode", in: source.document?.value) == .string("execute"))
        let nested = try originalResult(source)
        #expect(Fixture.field("payload", in: nested) == original.document?.value)
        #expect(Fixture.field("text", in: nested) == .string(text))
        let retainedText = try #require(MCPBatchTaskInputValue.string(Fixture.field("text", in: nested)))
        #expect(retainedText.utf8.elementsEqual(text.utf8))
        let retainedBytes = try #require(original.document?.originalUTF8)
        #expect(source.document?.originalUTF8.range(of: retainedBytes) != nil)
        #expect(Fixture.field("isError", in: nested) == flag.map(MCPJSONValue.boolean))
        #expect(source.originalIsError == (flag == true ? true : nil))
        #expect(source.originalText.contains("1E9999"))
    }

    @Test(arguments: ["malformed", "unknown"])
    func unreadableAndUnsupportedRetainAvailableOriginalEvidence(kind: String) async throws {
        let request = try Sequence.request(count: 1)
        let original = try Sequence.source(request.items[0], kind: kind)
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request), executor: { _ in
            .init(source: original)
        })
        let report = try await batch.run(request)
        let source = try MCPBatchTaskResult.execution(request, report: report)
        let nested = try originalResult(source)
        #expect(Fixture.field("text", in: nested) == .string(original.originalText))
        #expect(Fixture.field("payload", in: nested) == original.document?.value)
        #expect(Fixture.field("isError", in: nested) == original.originalIsError.map(MCPJSONValue.boolean))
        #expect(Fixture.field("summary", in: source.document?.value) == .string("evidence_unavailable"))
        #expect(source.originalIsError == true)
    }

    @Test func skippedMappingsDoNotInventAcceptanceOrReceipts() async throws {
        let request = try Sequence.request(count: 3)
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Sequence.prepared(request), executor: { item in
            .init(source: try Sequence.source(item, kind: "rejected"))
        })
        let report = try await batch.run(request)
        let source = try MCPBatchTaskResult.execution(request, report: report)
        guard case .array(let items) = Fixture.field("items", in: source.document?.value) else {
            Issue.record("Expected mapped entries"); return
        }
        #expect(items.count == 3)
        for index in 1...2 {
            #expect(Fixture.field("state", in: items[index]) == .string("not_attempted"))
            #expect(Fixture.field("itemId", in: items[index]) == .string(request.items[index].itemId))
            let mapped = try #require(MCPBatchTaskInputValue.string(Fixture.field("taskId", in: items[index])))
            let original = try #require(request.items[index].command.arguments["taskId"] as? String)
            #expect(mapped.utf8.elementsEqual(original.utf8))
            #expect(UUID(uuidString: mapped) == request.items[index].targetTaskId)
            for name in ["originalResult", "accepted", "record", "receipt", "replayExpiresAt"] {
                #expect(Fixture.field(name, in: items[index]) == nil)
            }
        }
        #expect(Fixture.field("atomicity", in: source.document?.value) == .string("per_item"))
    }

    @Test func modernStructuredPayloadIsTheSameLogicalSourceOnce() async throws {
        let request = try Sequence.request(count: 1)
        let prepared = try Sequence.prepared(request)
        let batch = MCPBatchTaskCoordinator(preparedResponse: prepared, executor: { item in
            .init(source: try Sequence.source(item))
        })
        let report = try await batch.run(request)
        let source = try MCPBatchTaskResult.execution(request, report: report)
        let bytes = try MCPResultProviderSelection.encode(outcome: .init(source: source, context: prepared.context),
                                                          id: .string("aggregate.rpc"), metadata: nil)
        let result = try Fixture.result(bytes)
        let structured = Fixture.field("structuredContent", in: result)
        #expect(Fixture.field("payload", in: Fixture.field("source", in: structured)) == source.document?.value)
        #expect(Fixture.field("isError", in: result) == nil)
        guard case .array(let content) = Fixture.field("content", in: result) else {
            Issue.record("Expected compatible text"); return
        }
        #expect(Fixture.field("text", in: content[0]) == .string(source.originalText))
    }

    @Test func previewAndShapeDiagnosticsHaveIndependentErrorFlags() throws {
        let fixture = try MCPBatchTaskCoordinatorFixture()
        let input = try MCPJSONDocument.parse(JSONSerialization.data(withJSONObject:
            ["mode": "dry_run", "items": [fixture.item(0)]]))
        guard case .valid(let request) = try MCPBatchTaskRequest.parse(input) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        let report = try MCPBatchTaskPreview.evaluate(request, container: fixture.owner.container,
                                                     persistence: PersistenceAvailability())
        let preview = try MCPBatchTaskResult.preview(request, report: report)
        #expect(preview.originalIsError == nil)
        #expect(Fixture.field("mode", in: preview.document?.value) == .string("dry_run"))
        #expect(Fixture.field("summary", in: preview.document?.value) == .string("preview_valid"))
        #expect(Fixture.field("observation", in: preview.document?.value) == .string("saved_local_store"))
        #expect(Fixture.field("confirmedCommittedCount", in: preview.document?.value) == nil)
        let rejected = try MCPBatchTaskResult.invalidInput([.init(index: 1, itemId: "caller", field: "taskId",
                                                                 code: "INVALID_INPUT")])
        #expect(rejected.originalIsError == true)
        #expect(Fixture.field("confirmedCommittedCount", in: rejected.document?.value) == nil)
        #expect(Fixture.field("accepted", in: rejected.document?.value) == nil)
        #expect(Fixture.field("summary", in: rejected.document?.value) == .string("rejected_input"))
        #expect(fixture.saveStages.isEmpty && !fixture.owner.context.hasChanges)
    }

    @Test func realCommitThenEncodingFailureSelectsReadyBytesWithoutReencoding() async throws {
        let fixture = try MCPBatchTaskCoordinatorFixture()
        let request = try fixture.request([fixture.item(0, changes: ["name": "Real durable effect"])])
        let prepared = try Sequence.prepared(request)
        let expected = try MCPResultEncoder.prepareMutationFallback(id: .string("task9.request"),
            source: MCPBatchTaskFallback.source(items: recovery(request)), context: prepared.context, metadata: nil)
        let batch = MCPBatchTaskCoordinator(preparedResponse: prepared,
                                           writeCoordinator: try #require(fixture.coordinator))
        let report = try await batch.run(request)
        #expect(report.confirmedCommittedCount == 1)
        let source = try MCPBatchTaskResult.execution(request, report: report)
        let counts = MCPBatchTaskEncodingCounts()
        let context = prepared.context
        let selected = try await prepared.select(encodeOutcome: { _, _, _ in
            counts.record("encode"); throw MCPResultBoundaryError.resourceLimit
        }, dispatch: { .init(source: source, context: context) })
        #expect(try Fixture.reconciliation(selected) == expected)
        #expect(counts.snapshot().encode == 1)
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.name == "Real durable effect")
        let suppressed = try await prepared.select(shouldDeliver: { false }, dispatch: {
            Issue.record("Suppressed delivery before dispatch must execute nothing")
            throw MCPResultBoundaryError.unsupportedEvidence
        })
        guard case .suppressed = suppressed else { Issue.record("Expected delivery suppression"); return }
    }

    @Test func nestedDepthOverflowAfterRealCommitUsesCompactFallback() async throws {
        let fixture = try MCPBatchTaskCoordinatorFixture()
        let giant = String(repeating: "giant-id", count: 30_000)
        var value = try fixture.item(0)
        value["itemId"] = giant
        let request = try fixture.request([value])
        let prepared = try Sequence.prepared(request)
        let source = try await fixture.source(request.items[0])
        let tail = ",\"deep\":" + String(repeating: "[", count: 31) + "null" + String(repeating: "]", count: 31) + "}"
        let original = try MCPResultAdapter.source(text: String(source.originalText.dropLast()) + tail,
            isError: source.originalIsError, origin: .retainedJSON, evidence: .established)
        #expect(original.document != nil)
        let batch = MCPBatchTaskCoordinator(preparedResponse: prepared, executor: { _ in .init(source: original) })
        let report = try await batch.run(request)
        #expect(report.confirmedCommittedCount == 1)
        let selected = try await prepared.select(dispatch: { @MainActor in
            let aggregate = try MCPBatchTaskResult.execution(request, report: report)
            return .init(source: aggregate, context: prepared.context)
        })
        let bytes = try Fixture.reconciliation(selected)
        let wire = try #require(String(data: bytes, encoding: .utf8))
        #expect(wire.contains("serialization_failed") && !wire.contains(giant) && !wire.contains("deep"))
        #expect(try fixture.durableTasks().first { $0.id == fixture.tasks[0].id }?.taskDescription ==
            "Canonical description")
    }

    private func originalResult(_ source: MCPResultSource) throws -> MCPJSONValue {
        guard case .array(let items) = Fixture.field("items", in: source.document?.value) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        return try #require(Fixture.field("originalResult", in: items[0]))
    }

    private func recovery(_ request: MCPBatchTaskRequest) -> [MCPBatchRecoveryItem] {
        request.items.map { .init(index: $0.index, itemId: $0.itemId, operation: $0.operation,
            originalKey: .init(tool: $0.command.tool, idempotencyKey: $0.command.key), targetTaskId: $0.targetTaskId) }
    }
}
#endif
