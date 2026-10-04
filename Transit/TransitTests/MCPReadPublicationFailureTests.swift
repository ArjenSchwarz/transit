#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadPublicationFailureTests {
    nonisolated private enum EncodingFailure: Error { case injected }

    @Test(arguments: [false, true])
    // swiftlint:disable:next function_body_length
    func outerEncodingFailureDiscardsActualPrivateOrdinaryCandidate(operationAware: Bool) async throws {
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
        let failingEncoder: @Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data = { tool, id in
            #expect(id == rpc.id)
            #expect(tool.publications.count == 1)
            let privateState = try domain.accounting(for: storeID)
            #expect(privateState.visibleEntries == 0 && privateState.pendingEntries == 1)
            #expect(privateState.pendingBytes > 0)
            throw EncodingFailure.injected
        }
        let operationEncoder: (@Sendable (MCPPreparedToolRead, JSONRPCId, MCPReadOperation) throws -> Data)?
        if operationAware {
            operationEncoder = { tool, id, operation in
                #expect(operation.shouldContinue())
                return try failingEncoder(tool, id)
            }
        } else { operationEncoder = nil }
        let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: handler,
            coordinator: handler.readCoordinator, admittedAt: .now, encode: { tool, id in
                #expect(!operationAware, "Operation-aware encoding must supersede the normal encoder")
                return try failingEncoder(tool, id)
            }, encodeWithOperation: operationEncoder, encodeConstantToolFailure: { tool, id in
                #expect(id == rpc.id)
                #expect(tool.publications.isEmpty && tool.result.isError == true)
                return try MCPBoundedReadDispatcher.encodeResult(tool, id: id)
            })
        let deadline = ContinuousClock.now + .seconds(1)
        while handler.readCoordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
        #expect(handler.readCoordinator.unfinishedCount == 0)
        let after = try domain.accounting(for: storeID)
        #expect(after.visibleEntries == 0 && after.visibleBytes == 0)
        #expect(after.pendingEntries == 0 && after.pendingBytes == 0)
        let decoded = try JSONSerialization.jsonObject(with: bytes)
        let response = try #require(decoded as? [String: Any])
        #expect(response["id"] as? String == "outer-encoding-\"\\failure")
        let tool = try #require(response["result"] as? [String: Any])
        let metadata = try #require((tool["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(metadata["category"] as? String == "serialization_failure")
        #expect(metadata["snapshotId"] == nil && metadata["asOf"] == nil)
        #expect(try MCPTestHelpers.decodeHTTPToolResult(response)["error"] as? [String: String]
            == ["code": "QUERY_FAILED", "message": "QUERY_FAILED"])
    }

    @Test(arguments: [false, true])
    func normalEncoderReturnsFullBytesWithOriginalIdentity(operationAware: Bool) async throws {
        let owner = try TestModelContainer()
        let (handler, store) = try makeHandler(owner)
        let rpc = request(arguments: [:])
        let read = try #require(MCPBoundedReadDispatcher.classify(rpc))
        let id = try #require(rpc.id)
        let encoder: @Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data = { tool, receivedID in
            #expect(receivedID == id)
            #expect(tool.frozenMetadataBytes != nil)
            var bytes = try MCPBoundedReadDispatcher.encodeResult(tool, id: receivedID)
            bytes.append(Data("\n".utf8))
            return bytes
        }
        let operationEncoder: (@Sendable (MCPPreparedToolRead, JSONRPCId, MCPReadOperation) throws -> Data)?
        if operationAware {
            operationEncoder = { tool, receivedID, operation in
                #expect(operation.shouldContinue())
                return try encoder(tool, receivedID)
            }
        } else { operationEncoder = nil }
        let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: handler,
            coordinator: handler.readCoordinator, admittedAt: .now, encode: { tool, receivedID in
                #expect(!operationAware)
                return try encoder(tool, receivedID)
            }, encodeWithOperation: operationEncoder)
        await drain(handler.readCoordinator)
        #expect(bytes.last == 10, "The exact full response bytes from the selected encoder must survive")
        let decoded = try JSONSerialization.jsonObject(with: bytes)
        let frame = try #require(decoded as? [String: Any])
        #expect(frame["id"] as? String == "encoder-hook")
        let tool = try #require(frame["result"] as? [String: Any])
        #expect(tool["_meta"] != nil)
        #expect(try store.domain.accounting(for: store.publicationStoreID).pendingEntries == 0)
        withExtendedLifetime(owner) {}
    }

    @Test func constantEncoderFailurePreventsCaptureAndAdmission() async throws {
        let owner = try TestModelContainer()
        let source = MCPReadHookCaptureProbe(owner: owner)
        let (handler, store) = try makeHandler(owner, source: source)
        let rpc = request(arguments: [:])
        let read = try #require(MCPBoundedReadDispatcher.classify(rpc))
        do {
            _ = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: handler,
                coordinator: handler.readCoordinator, admittedAt: .now, encode: { _, _ in
                    Issue.record("Normal encoder ran after constant preparation failed")
                    return Data()
                }, encodeConstantToolFailure: { _, id in
                    #expect(id == rpc.id)
                    throw EncodingFailure.injected
                })
            Issue.record("Constant encoder failure did not propagate before admission")
        } catch EncodingFailure.injected { } catch { Issue.record("Unexpected error: \(error)") }
        #expect(handler.readCoordinator.unfinishedCount == 0 && source.calls == 0)
        let state = try store.domain.accounting(for: store.publicationStoreID)
        #expect(state.pendingEntries == 0 && state.visibleEntries == 0)
        withExtendedLifetime(owner) {}
    }

    @Test func malformedArgumentsKeepSeparateProtocolFailure() async throws {
        let owner = try TestModelContainer()
        let (handler, _) = try makeHandler(owner)
        let rpc = request(arguments: "malformed")
        let read = try #require(MCPBoundedReadDispatcher.classify(rpc))
        let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: handler,
            coordinator: handler.readCoordinator, admittedAt: .now, encodeWithOperation: { _, _, _ in
                Issue.record("Malformed protocol parameters reached normal tool encoding")
                return Data()
            }, encodeConstantToolFailure: { tool, id in
                #expect(tool.result.isError == true)
                return try MCPBoundedReadDispatcher.encodeResult(tool, id: id)
            })
        await drain(handler.readCoordinator)
        let decoded = try JSONSerialization.jsonObject(with: bytes)
        let frame = try #require(decoded as? [String: Any])
        #expect(frame["id"] as? String == "encoder-hook" && frame["result"] == nil)
        #expect((frame["error"] as? [String: Any])?["code"] as? Int == JSONRPCErrorCode.invalidParams)
        withExtendedLifetime(owner) {}
    }

    private func request(arguments: Any) -> JSONRPCRequest {
        JSONRPCRequest(jsonrpc: "2.0", id: .string("encoder-hook"), method: "tools/call",
            params: AnyCodable(["name": "get_projects", "arguments": arguments]))
    }

    private func makeHandler(_ owner: TestModelContainer, source: (any MCPReadCaptureSource)? = nil) throws
        -> (MCPToolHandler, MCPTaskQuerySnapshotStore) {
        let env = try MCPTestHelpers.makeEnv()
        let store = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: source ?? MCPReadCaptureBuilder(container: owner.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false,
                storeIdentifier: nil), snapshots: store)
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings, readService: service)
        return (handler, store)
    }

    private func drain(_ coordinator: MCPReadCoordinator) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
    }

}

@MainActor private final class MCPReadHookCaptureProbe: MCPReadCaptureSource {
    let builder: MCPReadCaptureBuilder
    var calls = 0
    init(owner: TestModelContainer) {
        builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
    }
    func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
        calls += 1
        return try builder.capture(request)
    }
}
#endif
