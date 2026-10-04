#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadModernPageBindingTests {
    @Test func allPrivatePagesPrepareBeforeReservationAndReplayUsesSameSealedOwner() async throws {
        let fixture = try Fixture()
        let observed = NIOLockedValueBox<[MCPResultPreparedPage]>([])
        let domain = fixture.store.domain
        let storeID = fixture.store.publicationStoreID
        let service = fixture.service { pages, tool, operation in
            #expect(tool == "query_tasks" && pages.count == 2 && operation.shouldContinue())
            let state = try domain.accounting(for: storeID)
            #expect(state.pendingBytes == 0 && state.visibleBytes == 0)
            let owners = try Self.prepare(pages)
            observed.withLockedValue { $0 = owners }
            return owners
        }
        let first = try await fixture.execute(service, arguments: ["detailLevel": "summary",
            "includeComments": false, "limit": 1], id: .string("initial"))
        await fixture.drain()
        let frameValue = try JSONSerialization.jsonObject(with: first)
        let frame = try #require(frameValue as? [String: Any])
        let payload = try MCPTestHelpers.decodeHTTPToolResult(frame)
        let cursor = try #require(payload["nextCursor"] as? String)
        let retained = try fixture.store.retainedPage(for: cursor)
        let owner = try #require(retained.preparedResultPage)
        let prepared = observed.withLockedValue { $0 }
        #expect(prepared.count == 2 && owner === prepared[1])
        #expect(prepared[0].metadataOwner === prepared[1].metadataOwner)
        let raw = retained.metadataBytes
        let tasks = try fixture.models.context.fetch(FetchDescriptor<TransitTask>())
        tasks.first?.name = "Saved later edit"
        try fixture.models.context.save()
        fixture.source.failure = .storageFailure
        let replay = try await fixture.execute(service, arguments: ["cursor": cursor])
        await fixture.drain()
        #expect(fixture.source.calls == 1)
        #expect(try fixture.store.retainedPage(for: cursor).preparedResultPage === owner)
        #expect(try fixture.store.retainedPage(for: cursor).metadataBytes == raw)
        let expected = try MCPResultEncoder.encode(fragment: owner.fragment, id: .string("fixture"))
        #expect(replay == expected)
        // Direct replay trusts the sealed fragment, even when raw metadata cannot be typed-decoded.
        let opaque = MCPPreparedToolRead(preparedResultPage: owner, frozenMetadataBytes: Data("not-json".utf8))
        #expect(opaque.encodedToolResult == owner.fragment.encodedResult)
        #expect(opaque.frozenMetadataBytes == Data("not-json".utf8) && opaque.result.metadata == nil)
    }

    @Test(arguments: [false, true])
    func failedModernPreparationNeverReservesOrInventsSuccess(capacity: Bool) async throws {
        let fixture = try Fixture()
        let service = fixture.service { _, _, _ in
            if capacity { throw MCPResultPreparationError.retentionCapacity }
            return []
        }
        let bytes = try await fixture.execute(service, arguments: ["detailLevel": "summary",
            "includeComments": false, "limit": 1])
        await fixture.drain()
        let value = try JSONSerialization.jsonObject(with: bytes)
        let frame = try #require(value as? [String: Any])
        let payload = try MCPTestHelpers.decodeHTTPToolResult(frame)
        #expect((payload["error"] as? [String: Any])?["code"] as? String
            == (capacity ? "QUERY_CAPACITY_EXCEEDED" : "QUERY_FAILED"))
        let state = try fixture.store.domain.accounting(for: fixture.store.publicationStoreID)
        #expect(state.pendingBytes == 0 && state.visibleBytes == 0)
        #expect(fixture.source.calls == 1)
    }

    @Test func siblingNewRootsSharingFreshOwnersRejectBeforeTransfer() throws {
        let fixture = try Fixture()
        let tools = try ["[]", "null"].map { try MCPPreparedToolRead(text: $0) }
        let pages = try Self.prepare(tools)
        let bundle = try MCPResultPreparation.prepare(pages: pages,
            budget: MCPResultRetentionBudget(store: .ordinary, originalCaptureIndexBytes: 0,
                                              visibleBytes: 0, pendingBytes: 0))
        let deadline = ContinuousClock.now + .seconds(300)
        let firstCandidate = try fixture.store.prepare(preparedBundle: bundle, cursors: [UUID().uuidString],
            deadline: deadline, operationID: UUID(), metadataBytes: nil, policy: .cached)
        let first = try #require(firstCandidate)
        let secondCandidate = try fixture.store.prepare(preparedBundle: bundle, cursors: [UUID().uuidString],
            deadline: deadline, operationID: UUID(), metadataBytes: nil, policy: .cached)
        let second = try #require(secondCandidate)
        #expect(throws: PublicationRejection.busy) {
            try fixture.store.prepareAggregate([first, second], in: fixture.store.domain)
        }
        let state = try fixture.store.domain.accounting(for: fixture.store.publicationStoreID)
        #expect(state.pendingBytes == bundle.charge.totalBytes * 2 && state.visibleBytes == 0)
        let (_, retired) = fixture.store.domain.withLockRetainingRetirement {
            first.discardLocked(in: fixture.store.domain)
            second.discardLocked(in: fixture.store.domain)
        }
        withExtendedLifetime(retired) {}
        #expect(try fixture.store.domain.accounting(for: fixture.store.publicationStoreID).pendingBytes == 0)
    }

    nonisolated private static func prepare(_ tools: [MCPPreparedToolRead]) throws -> [MCPResultPreparedPage] {
        let metadata: MCPResultPreparedMetadata?
        if let first = tools.first,
           let value = try MCPResultProviderAdapters.metadata(result: first.result,
                                                               frozenReadBytes: first.frozenMetadataBytes) {
            metadata = try MCPResultPreparation.metadata(value: value)
        } else { metadata = nil }
        return try tools.map { tool in
            guard let text = tool.result.content.first?.text else { throw MCPReadCaptureError.serializationFailure }
            return try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: text,
                isError: tool.result.isError, origin: .generatedJSON, evidence: .established,
                context: MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                    mutationRecovery: nil, entityPositions: []), metadataOwner: metadata))
        }
    }

    @MainActor private struct Fixture {
        let models: TestModelContainer
        let source: Source
        let store: MCPTaskQuerySnapshotStore
        let coordinator: MCPReadCoordinator
        init() throws {
            models = try TestModelContainer()
            models.context.autosaveEnabled = false
            let project = Project(name: "Frozen", description: "", gitRepo: nil, colorHex: "blue")
            models.context.insert(project)
            for number in 1...2 {
                models.context.insert(TransitTask(name: "Saved \(number)", type: .feature,
                    project: project, displayID: .permanent(number)))
            }
            try models.context.save()
            source = Source(models)
            store = MCPTaskQuerySnapshotStore()
            coordinator = MCPReadCoordinator(domain: store.domain)
        }
        func service(_ preparer: @escaping MCPReadPagePreparer) -> MCPReadService {
            MCPReadService(source: source, monitor: MCPImportEvidenceMonitor(syncActive: false,
                storeIdentifier: nil), snapshots: store, pagePreparer: preparer)
        }
        func execute(_ service: MCPReadService, arguments: [String: Any],
                     id: JSONRPCId = .string("fixture")) async throws -> Data {
            let fields = arguments.mapValues(AnyCodable.init)
            return await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
                do {
                    let tool = try await self.prepare(service, fields: fields, operation: operation)
                    let bytes: Data
                    if let page = tool.preparedResultPage {
                        bytes = try MCPResultEncoder.encode(fragment: page.fragment, id: id)
                    } else { bytes = try MCPBoundedReadDispatcher.encodeResult(tool, id: id) }
                    return PreparedReadResult(encodedResponse: bytes, publications: tool.publications,
                        publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
                } catch {
                    Issue.record("Unexpected fixture failure: \(error)")
                    return PreparedReadResult(encodedResponse: Data(), publications: [],
                        publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
                }
            }
        }
        private func prepare(_ service: MCPReadService, fields: [String: AnyCodable],
                             operation: MCPReadOperation) async throws -> MCPPreparedToolRead {
            try await service.prepare(tool: "query_tasks", arguments: fields.mapValues(\.value), operation: operation)
        }
        func drain() async {
            let deadline = ContinuousClock.now + .seconds(1)
            while coordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
            #expect(coordinator.unfinishedCount == 0)
            withExtendedLifetime(models) {}
        }
    }

    @MainActor private final class Source: MCPReadCaptureSource {
        let builder: MCPReadCaptureBuilder
        var failure: MCPReadCaptureError?
        var calls = 0
        init(_ models: TestModelContainer) {
            builder = MCPReadCaptureBuilder(container: models.container, fence: .actorOnlyTestFixture)
        }
        func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
            calls += 1
            if let failure { throw failure }
            return try builder.capture(request)
        }
    }
}
#endif
