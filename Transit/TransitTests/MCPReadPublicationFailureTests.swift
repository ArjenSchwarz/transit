#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadPublicationFailureTests {
    nonisolated private enum EncodingFailure: Error { case injected }

    @Test func outerEncodingFailureDiscardsActualPrivateOrdinaryCandidate() async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        fixture.context.insert(project)
        for number in 1...2 {
            fixture.context.insert(TransitTask(name: "Task \(number)", type: .feature,
                                              project: project, displayID: .permanent(number)))
        }
        try fixture.context.save()
        let env = try MCPTestHelpers.makeEnv()
        let store = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: MCPReadCaptureBuilder(container: fixture.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false,
            storeIdentifier: nil), snapshots: store)
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings, readService: service)
        let rpc = JSONRPCRequest(jsonrpc: "2.0", id: .string("outer-encoding-\"\\failure"), method: "tools/call",
            params: AnyCodable(["name": "query_tasks", "arguments": ["detailLevel": "summary",
                "includeComments": false, "limit": 1]] as [String: Any]))
        let read = try #require(MCPBoundedReadDispatcher.classify(rpc))
        let domain = store.domain
        let storeID = store.publicationStoreID
        let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: handler,
            coordinator: handler.readCoordinator, admittedAt: .now, encode: { tool, _ in
                #expect(tool.publications.count == 1)
                let privateState = try domain.accounting(for: storeID)
                #expect(privateState.visibleEntries == 0 && privateState.pendingEntries == 1)
                #expect(privateState.pendingBytes > 0)
                throw EncodingFailure.injected
            })
        let deadline = ContinuousClock.now + .seconds(1)
        while handler.readCoordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
        #expect(handler.readCoordinator.unfinishedCount == 0)
        let after = try domain.accounting(for: storeID)
        #expect(after.visibleEntries == 0 && after.visibleBytes == 0)
        #expect(after.pendingEntries == 0 && after.pendingBytes == 0)
        let response = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(response["id"] as? String == "outer-encoding-\"\\failure")
        let tool = try #require(response["result"] as? [String: Any])
        let metadata = try #require((tool["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(metadata["category"] as? String == "serialization_failure")
        #expect(metadata["snapshotId"] == nil && metadata["asOf"] == nil)
        #expect(try MCPTestHelpers.decodeHTTPToolResult(response)["error"] as? [String: String]
            == ["code": "QUERY_FAILED", "message": "QUERY_FAILED"])
    }
}
#endif
