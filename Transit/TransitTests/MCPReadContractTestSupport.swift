#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor final class MCPReadContractSource: MCPReadCaptureSource {
    let builder: MCPReadCaptureBuilder
    var calls = 0
    var failure: MCPReadCaptureError?
    init(owner: TestModelContainer) {
        builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
    }
    func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
        calls += 1
        if let failure { throw failure }
        return try builder.capture(request)
    }
}

@MainActor struct MCPReadContractFixture {
    let owner: TestModelContainer
    let source: MCPReadContractSource
    let store: MCPTaskQuerySnapshotStore
    let service: MCPReadService
    let coordinator: MCPReadCoordinator

    init(syncActive: Bool = false, diagnostics: MCPReadDiagnosticSink = .disabled) throws {
        owner = try TestModelContainer()
        owner.context.autosaveEnabled = false
        let project = Project(name: "Contract", description: "", gitRepo: nil, colorHex: "blue")
        owner.context.insert(project)
        for number in 1...2 {
            owner.context.insert(TransitTask(name: "Saved \(number)", type: .feature,
                                            project: project, displayID: .permanent(number)))
        }
        try owner.context.save()
        source = MCPReadContractSource(owner: owner)
        store = MCPTaskQuerySnapshotStore()
        service = MCPReadService(source: source, monitor: MCPImportEvidenceMonitor(
            syncActive: syncActive, storeIdentifier: syncActive ? "unproved-fixture" : nil),
            snapshots: store, diagnostics: diagnostics, pagePreparer: { pages, tool, operation in
                try MCPModernProviderBinding.prepareReadPages(pages, tool: tool, operation: operation)
            })
        coordinator = MCPReadCoordinator(domain: store.domain, diagnostics: diagnostics)
    }

    func execute(arguments: [String: Any], operationID: UUID = UUID()) async throws -> Data {
        let request = MCPReadToolRequest(tool: "query_tasks", arguments: arguments.mapValues(AnyCodable.init))
        let timeout = try Self.failure("READ_TIMEOUT", id: operationID)
        let busy = try Self.failure("READ_BUSY", id: operationID)
        let errors = try MCPBoundedReadDispatcher.publicationErrors(
            for: request, id: .string(operationID.uuidString), busy: busy,
            encodeConstantToolFailure: { tool, id in
                try MCPModernProviderBinding.read(tool, id: id, tool: request.tool)
            })
        return await coordinator.execute(timeout: timeout, busy: busy,
            admission: MCPReadAdmission(operationID: operationID), diagnosticTool: request.tool) { operation in
            do {
                operation.beginActorQueue()
                let tool = try await self.prepare(request, operation: operation)
                let bytes = try MCPBoundedReadDispatcher.encodeMeasured(tool,
                    id: .string(operationID.uuidString), operation: operation) { prepared, id, operation in
                        try MCPModernProviderBinding.read(prepared, id: id, tool: request.tool, operation: operation)
                    }
                return PreparedReadResult(encodedResponse: bytes, publications: tool.publications,
                    publicationErrors: errors, diagnosticOutcome: tool.result.isError == true ? .failure : .success)
            } catch {
                Issue.record("Caller fixture preparation failed: \(error)")
                return PreparedReadResult(encodedResponse: timeout, publications: [], publicationErrors: errors)
            }
        }
    }

    private func prepare(_ request: MCPReadToolRequest,
                         operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
        try await service.prepare(tool: request.tool,
                                  arguments: request.arguments.mapValues(\.value), operation: operation)
    }

    /// Synchronous bounded wait invoked on a detached worker, never on MainActor.
    nonisolated static func wait(_ semaphore: DispatchSemaphore, seconds: Double) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + seconds)
    }

    static func failure(_ code: String, id: UUID) throws -> Data {
        let tool = try MCPPreparedToolRead(text: IntentHelpers.encodeJSON(["error": ["code": code]]), isError: true)
        return try MCPModernProviderBinding.read(tool, id: .string(id.uuidString), tool: "query_tasks")
    }

    static func result(_ bytes: Data) throws -> [String: Any] {
        let decoded = try JSONSerialization.jsonObject(with: bytes)
        let frame = try #require(decoded as? [String: Any])
        return try #require(frame["result"] as? [String: Any])
    }

    static func payload(_ bytes: Data) throws -> [String: Any] {
        let decoded = try JSONSerialization.jsonObject(with: bytes)
        let frame = try #require(decoded as? [String: Any])
        return try MCPTestHelpers.decodeHTTPToolResult(frame)
    }

    static func metadata(_ bytes: Data) throws -> [String: Any] {
        let tool = try result(bytes)
        return try #require((tool["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
    }

    func drain() async {
        let limit = ContinuousClock.now + .seconds(2)
        while coordinator.unfinishedCount != 0 && .now < limit { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
        withExtendedLifetime(owner) {}
    }
}

nonisolated final class MCPReadDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [MCPReadDiagnosticEvent] = []
    func append(_ event: MCPReadDiagnosticEvent) {
        lock.lock()
        stored.append(event)
        lock.unlock()
    }
    var events: [MCPReadDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
#endif
