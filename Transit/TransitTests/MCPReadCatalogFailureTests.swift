#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadCatalogFailureTests {
    @Test(arguments: ["get_projects", "query_milestones"],
          ["storage_failure", "serialization_failure", "incoherent_capture"])
    func executionFaultKeepsMachineCodeAndFailureEvidence(tool: String, category: String) async throws {
        let source = Source(category: category)
        let store = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: source,
            monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil), snapshots: store,
            pagePreparer: { pages, tool, operation in
                try MCPModernProviderBinding.prepareReadPages(pages, tool: tool, operation: operation)
            })
        let coordinator = MCPReadCoordinator(domain: store.domain)
        let operationID = UUID()
        let rpcID = JSONRPCId.string(operationID.uuidString)
        let receipt = DispatchSemaphore(value: 0)
        let request = MCPReadToolRequest(tool: tool, arguments: ["readPolicy": AnyCodable("cached")])
        let timeout = try Self.fallback("READ_TIMEOUT", tool: tool, id: rpcID)
        let busy = try Self.fallback("READ_BUSY", tool: tool, id: rpcID)
        let errors = try MCPBoundedReadDispatcher.publicationErrors(for: request, id: rpcID, busy: busy,
            encodeConstantToolFailure: { prepared, id in
                try MCPModernProviderBinding.read(prepared, id: id, tool: tool)
            })
        let response = await coordinator.execute(timeout: timeout, busy: busy,
            admission: MCPReadAdmission(operationID: operationID, physicalCompletion: { receipt.signal() }),
            diagnosticTool: tool) { operation in
                do {
                    let prepared = try await service.prepare(tool: tool, arguments: ["readPolicy": "cached"],
                                                             operation: operation)
                    #expect(prepared.publications.isEmpty)
                    let owners = try MCPModernProviderBinding.prepareReadPages([prepared], tool: tool,
                                                                               operation: operation)
                    let owner = try #require(owners.first)
                    #expect(owner.source.originalIsError == true)
                    let bytes = try MCPBoundedReadDispatcher.encodeMeasured(prepared, id: rpcID,
                        operation: operation) { prepared, id, operation in
                            try MCPModernProviderBinding.read(prepared, id: id, tool: tool, operation: operation)
                        }
                    return PreparedReadResult(encodedResponse: bytes, publications: prepared.publications,
                                              publicationErrors: errors, diagnosticOutcome: .failure)
                } catch {
                    Issue.record("Unexpected catalog failure preparation/encoding fault: \(error)")
                    return PreparedReadResult(encodedResponse: timeout, publications: [], publicationErrors: errors)
                }
            }
        let completed = await Task.detached { Self.waitForReceipt(receipt) }.value
        #expect(completed == .success)
        #expect(coordinator.unfinishedCount == 0)
        #expect(source.calls == 1)
        let accounting = try store.domain.accounting(for: store.publicationStoreID)
        #expect(accounting.visibleEntries == 0 && accounting.pendingEntries == 0)
        #expect(accounting.visibleBytes == 0 && accounting.pendingBytes == 0)

        try Self.assertFailure(response, operationID: operationID, category: category)
    }

    private static func assertFailure(_ response: Data, operationID: UUID, category: String) throws {
        let decoded = try JSONSerialization.jsonObject(with: response)
        let frame = try #require(decoded as? [String: Any])
        #expect(frame["id"] as? String == operationID.uuidString)
        #expect(frame["error"] == nil)
        let result = try #require(frame["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        // Current baseline is valid plain text: absent JSON is a missing-code assertion,
        // never a thrown JSON parse/setup failure that could masquerade as behavioral RED.
        let logical = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        #expect((logical?["error"] as? [String: Any])?["code"] as? String == "READ_FAILED")
        #expect(logical?["projects"] == nil && logical?["milestones"] == nil)

        let metadata = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(metadata["category"] as? String == category)
        #expect(metadata["requestId"] as? String == operationID.uuidString)
        #expect(metadata["snapshotId"] == nil && metadata["asOf"] == nil)
        let read = try #require(metadata["read"] as? [String: Any])
        #expect(read["policy"] as? String == "cached")
        #expect(read["budgetMs"] as? Int == 5_000)
        let structured = try #require(result["structuredContent"] as? [String: Any])
        let presentation = try #require(structured["presentation"] as? [String: Any])
        #expect(presentation["errorCategory"] as? String == category)
        let provider = try #require(structured["source"] as? [String: Any])
        if (logical?["error"] as? [String: Any])?["code"] as? String == "READ_FAILED" {
            #expect(provider["kind"] as? String == "json")
        }
        if provider["kind"] as? String == "text" {
            #expect(provider["payload"] as? String == text)
        } else {
            #expect(provider["kind"] as? String == "json")
            let payload = try #require(provider["payload"] as? [String: Any])
            #expect((payload["error"] as? [String: Any])?["code"] as? String == "READ_FAILED")
            #expect(payload["projects"] == nil && payload["milestones"] == nil)
        }
    }

    nonisolated private static func waitForReceipt(_ receipt: DispatchSemaphore) -> DispatchTimeoutResult {
        receipt.wait(timeout: .now() + 2)
    }

    nonisolated private static func fallback(_ code: String, tool: String, id: JSONRPCId) throws -> Data {
        let prepared = try MCPPreparedToolRead(text: IntentHelpers.encodeJSON(["error": ["code": code]]), isError: true)
        return try MCPModernProviderBinding.read(prepared, id: id, tool: tool)
    }

    @MainActor private final class Source: MCPReadCaptureSource {
        let category: String
        var calls = 0
        init(category: String) { self.category = category }
        func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
            calls += 1
            switch category {
            case "serialization_failure": throw MCPReadCaptureError.serializationFailure
            case "incoherent_capture": throw MCPReadCaptureError.incoherentCapture
            default: throw MCPReadCaptureError.storageFailure
            }
        }
    }
}
#endif
