#if os(macOS)
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ConsolidationPreviewPublicationTests {
    @Test func injectedReadServiceProducesUsableReviewOnlyAfterResponseGate() async throws {
        let fixture = try ConsolidationPreviewFixture()
        let before = try fixture.capture()
        let bytes = await fixture.execute(tool: "preview_task_consolidation", arguments: fixture.arguments)
        let result = try fixture.payload(bytes)
        let id = try #require((result["reviewId"] as? String).flatMap(UUID.init(uuidString:)))
        let revision = try #require(result["reviewRevision"] as? String)
        let retained = try fixture.store.review(id: id, revision: revision, scope: fixture.scope, kind: .apply)
        #expect(!retained.proposalBytes.isEmpty && revision.hasPrefix("p1:"))
        #expect((result["originals"] as? [[String: Any]])?.count == 3)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(fixture.capture().originals, before.originals))
        #expect(fixture.base.observation.commitSaves == 0)
    }

    @Test func undoPreviewUsesRecordedOperationThroughSameSavedBoundary() async throws {
        let fixture = try ConsolidationPreviewFixture()
        _ = await fixture.base.execute()
        let operation = try #require(try fixture.capture().events.first?.operationId)
        let result = try fixture.payload(await fixture.execute(tool: "preview_task_consolidation_undo",
            arguments: ["operationId": operation.uuidString, "readPolicy": "cached"]))
        #expect(result["undoAvailable"] as? Bool == true)
        let id = try #require((result["reviewId"] as? String).flatMap(UUID.init(uuidString:)))
        let revision = try #require(result["reviewRevision"] as? String)
        _ = try fixture.store.review(id: id, revision: revision, scope: fixture.scope, kind: .undo)
        #expect(fixture.base.observation.commitSaves == 1)
    }

    @Test func metadataFreezingPreservesCompleteSupplementaryHistory() async throws {
        let fixture = try ConsolidationPreviewFixture()
        _ = await fixture.base.execute()
        let fields = ["taskIds": [fixture.base.base.source.id.uuidString], "detailLevel": "full",
                      "includeComments": true, "limit": 5, "readPolicy": "cached"] as [String: Any]
        let result = try fixture.payload(await fixture.execute(tool: "query_tasks", arguments: fields))
        let outcome = try #require((result["results"] as? [[String: Any]])?.first)
        let task = try #require(outcome["task"] as? [String: Any])
        #expect(task["consolidationHistoryCoverage"] as? String == "complete")
        #expect((task["consolidationHistory"] as? [[String: Any]])?.count == 1)
    }

    @Test func clearDuringPreparedResponseRejectsReviewAndReleasesPendingCharge() async throws {
        let fixture = try ConsolidationPreviewFixture()
        let result = await fixture.execute(tool: "preview_task_consolidation", arguments: fixture.arguments,
                                           clearBeforeGate: true)
        #expect(result == Data("rejected".utf8))
        #expect(fixture.store.retainedBytes == 0)
        #expect(try fixture.store.domain.accounting(for: fixture.store.publicationStoreID).pendingBytes == 0)
    }

    @Test func failedOuterEncodingDiscardsReviewWithoutDomainEffects() async throws {
        let fixture = try ConsolidationPreviewFixture()
        let before = try fixture.capture()
        let env = try MCPTestHelpers.makeEnv()
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings,
            readService: fixture.service, consolidationPreviewAdapter: fixture.adapter,
            readCoordinator: fixture.coordinator)
        let rpc = JSONRPCRequest(jsonrpc: "2.0", id: .string("preview-encoding"), method: "tools/call",
            params: AnyCodable(["name": "preview_task_consolidation", "arguments": fixture.arguments]))
        let read = MCPClassifiedRead(request: MCPReadToolRequest(tool: "preview_task_consolidation",
            arguments: fixture.arguments.mapValues(AnyCodable.init)), malformedArguments: false)
        let domain = fixture.store.domain, storeID = fixture.store.publicationStoreID
        let encoderCalls = Mutex(0)
        let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: handler,
            coordinator: fixture.coordinator, admittedAt: .now, encode: { tool, _ in
                encoderCalls.withLock { $0 += 1 }
                #expect(tool.publications.count == 1)
                let accounting = try domain.accounting(for: storeID)
                #expect(accounting.visibleEntries == 0 && accounting.pendingEntries == 1)
                throw PreviewEncodingFailure.injected
            })
        #expect(encoderCalls.withLock { $0 } == 1)
        let envelope = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let result = try #require(envelope["result"] as? [String: Any])
        let metadata = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(metadata["category"] as? String == "serialization_failure")
        #expect(fixture.store.retainedBytes == 0)
        #expect(try domain.accounting(for: storeID).pendingBytes == 0)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(fixture.capture().originals, before.originals))
    }

    @Test func completePreviewCapacityFailureLeavesNoReviewOrEffects() async throws {
        let fixture = try ConsolidationPreviewFixture(maxBytes: 1)
        let before = try fixture.capture()
        #expect(await fixture.execute(tool: "preview_task_consolidation", arguments: fixture.arguments)
            == Data("rejected".utf8))
        #expect(fixture.store.retainedBytes == 0)
        #expect(try fixture.store.domain.accounting(for: fixture.store.publicationStoreID).pendingBytes == 0)
        #expect(try ConsolidationPreviewFixture.sameSavedOriginals(fixture.capture().originals, before.originals))
    }

    @Test func cancelledPreparedPreviewNeverPublishesAndDrainsPhysicalSlot() async throws {
        let fixture = try ConsolidationPreviewFixture()
        #expect(await fixture.execute(tool: "preview_task_consolidation", arguments: fixture.arguments,
            cancelBeforeGate: true) == Data("timeout".utf8))
        let limit = ContinuousClock.now + .seconds(1)
        while fixture.coordinator.unfinishedCount != 0 && .now < limit { await Task.yield() }
        #expect(fixture.coordinator.unfinishedCount == 0 && fixture.store.retainedBytes == 0)
        #expect(try fixture.store.domain.accounting(for: fixture.store.publicationStoreID).pendingBytes == 0)
    }

    @Test func originalExpiredAdmissionNeverCapturesOrCreatesReview() async throws {
        let fixture = try ConsolidationPreviewFixture()
        #expect(await fixture.execute(tool: "preview_task_consolidation", arguments: fixture.arguments,
            admittedAt: .now - .seconds(10)) == Data("timeout".utf8))
        #expect(fixture.store.retainedBytes == 0 && fixture.base.observation.commitSaves == 0)
    }

    nonisolated private enum PreviewEncodingFailure: Error { case injected }

}

@MainActor final class ConsolidationPreviewFixture {
    let base: TaskConsolidationCommitFixture
    let store: MCPTaskQuerySnapshotStore
    let service: MCPReadService
    let adapter: MCPConsolidationPreviewAdapter
    let coordinator: MCPReadCoordinator
    let scope: String

    init(maxBytes: Int = 16 * 1_024 * 1_024) throws {
        store = MCPTaskQuerySnapshotStore(maxBytes: maxBytes)
        base = try TaskConsolidationCommitFixture()
        scope = try #require(base.coordinator.localScopeId)
        service = MCPReadService(source: MCPReadCaptureBuilder(container: base.base.owner.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false,
            storeIdentifier: nil), snapshots: store,
            pagePreparer: { try MCPModernProviderBinding.prepareReadPages($0, tool: $1, operation: $2) })
        adapter = MCPConsolidationPreviewAdapter(service: service, originScopeId: scope)
        coordinator = MCPReadCoordinator(domain: store.domain)
    }

    var arguments: [String: Any] {
        ["survivorTaskId": base.base.target.id.uuidString,
         "candidateTaskIds": [base.base.source.id.uuidString, base.extra.id.uuidString],
         "reason": "reviewed work", "preservation": [base.base.source.id.uuidString:
            ["retainedExplanation": "original description and comment retained"], base.extra.id.uuidString:
            ["retainedExplanation": "original metadata retained"]], "readPolicy": "cached"]
    }

    func capture() throws -> ConsolidationSavedEvidence {
        try TaskConsolidationSavedCapture(container: base.base.owner.container, fence: .actorOnlyTestFixture)
            .capture(selectedTaskIds: [base.base.target.id, base.base.source.id, base.extra.id])
    }

    func execute(tool: String, arguments: [String: Any], clearBeforeGate: Bool = false,
                 cancelBeforeGate: Bool = false, admittedAt: ContinuousClock.Instant = .now) async -> Data {
        let fields = arguments.mapValues(AnyCodable.init)
        return await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
            admittedAt: admittedAt) { [self] operation in
            await response(tool: tool, arguments: fields, operation: operation,
                clearBeforeGate: clearBeforeGate, cancelBeforeGate: cancelBeforeGate)
        }
    }

    private func response(tool: String, arguments: [String: AnyCodable], operation: MCPReadOperation,
                          clearBeforeGate: Bool, cancelBeforeGate: Bool) async -> PreparedReadResult {
        let failure = Data("rejected".utf8)
        let errors = PreencodedPublicationErrors(busy: failure, expired: failure, capacity: failure)
        let visibleBefore = store.retainedBytes
        do {
            let prepared = tool == "query_tasks"
                ? try await service.prepare(tool: tool, arguments: arguments.mapValues(\.value), operation: operation)
                : try await adapter.prepare(tool: tool, arguments: arguments.mapValues(\.value), operation: operation)
            #expect(store.retainedBytes == visibleBefore)
            if cancelBeforeGate { coordinator.stop() }
            if clearBeforeGate { store.clear() }
            return PreparedReadResult(encodedResponse: prepared.encodedToolResult,
                                      publications: prepared.publications, publicationErrors: errors)
        } catch {
            return PreparedReadResult(encodedResponse: failure, publications: [], publicationErrors: errors)
        }
    }

    static func sameSavedOriginals(_ lhs: [ConsolidationOriginal], _ rhs: [ConsolidationOriginal]) throws -> Bool {
        guard lhs.count == rhs.count, Set(lhs.map(\.id)) == Set(rhs.map(\.id)) else { return false }
        let decoder = JSONDecoder()
        for value in lhs {
            guard let other = rhs.first(where: { $0.id == value.id }),
                  value.fields == other.fields, value.revision == other.revision,
                  value.recordJSON == other.recordJSON, value.projectId == other.projectId,
                  try decoder.decode(PersistentIdentifier.self, from: value.physicalKey)
                    == decoder.decode(PersistentIdentifier.self, from: other.physicalKey),
                  try decoder.decode(PersistentIdentifier.self, from: value.projectPhysicalKey)
                    == decoder.decode(PersistentIdentifier.self, from: other.projectPhysicalKey) else { return false }
        }
        return true
    }

    func payload(_ bytes: Data) throws -> [String: Any] {
        let envelope = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let text = try #require((envelope["content"] as? [[String: Any]])?.first?["text"] as? String)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
#endif
