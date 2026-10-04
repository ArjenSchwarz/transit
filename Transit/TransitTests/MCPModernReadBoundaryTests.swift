#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPModernReadBoundaryTests {
    @Test func actualPagedServiceCallsPrivatePreparerBeforeAnyReservation() async throws {
        let models = try TestModelContainer()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        models.context.insert(project)
        for index in 1...2 {
            models.context.insert(TransitTask(name: "Saved \(index)", type: .feature, project: project,
                displayID: .permanent(index)))
        }
        try models.context.save()
        let snapshots = MCPTaskQuerySnapshotStore()
        let count = NIOLockedValueBox(0)
        let service = MCPReadService(source: MCPReadCaptureBuilder(container: models.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil),
            snapshots: snapshots, pagePreparer: { pages, tool, operation in
                count.withLockedValue { $0 += 1 }
                #expect(pages.count == 2 && tool == "query_tasks" && operation.shouldContinue())
                throw MCPReadCaptureError.serializationFailure
            })
        let coordinator = MCPReadCoordinator(domain: snapshots.domain)
        let output = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let result = try await service.prepare(tool: "query_tasks", arguments: [
                    "limit": 1, "detailLevel": "full", "includeComments": false, "readPolicy": "cached"
                ], operation: operation)
                return await MainActor.run {
                    defer { snapshots.domain.withLock {
                        for publication in result.publications { publication.discardLocked(in: snapshots.domain) }
                    } }
                    #expect(count.withLockedValue { $0 } == 1)
                    #expect(result.publications.isEmpty)
                    guard case .some(.failure(let failure)) = result.result.metadata?.read else {
                        Issue.record("Private whole-page encoder fault escaped as a capture success")
                        return Self.response(Data("failed".utf8))
                    }
                    #expect(failure.category == .serializationFailure)
                    #expect(try snapshots.domain.accounting(for: snapshots.publicationStoreID).pendingBytes == 0)
                    return Self.response(Data("failed-whole".utf8))
                }
            } catch {
                Issue.record("Actual paged service unexpectedly threw: \(error)")
                return Self.response(Data("failed".utf8))
            }
        }
        #expect(output == Data("failed-whole".utf8))
        for _ in 0..<100 where coordinator.unfinishedCount != 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(coordinator.unfinishedCount == 0 && snapshots.retainedBytes == 0)
    }

    @Test func explicitMissingSelectorAndStorageFaultNeverProducePrivatePages() throws {
        let models = try TestModelContainer()
        let store = MCPTaskQuerySnapshotStore()
        let source = MCPReadCaptureBuilder(container: models.container, fence: .actorOnlyTestFixture)
        #expect(throws: MCPReadCaptureError.projectNotFound) {
            try source.capture(ReadCaptureRequest(projectSelectors: [.name("Absent")], selection: .portfolio,
                completeness: .completePortfolio, includeComments: false))
        }
        let failing = MCPReadCaptureBuilder(container: models.container, fence: .actorOnlyTestFixture,
            fetchTasks: { _ in throw StorageFault.unavailable })
        #expect(throws: MCPReadCaptureError.storageFailure) {
            try failing.capture(ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                completeness: .completePortfolio, includeComments: false))
        }
        #expect(store.retainedBytes == 0)
    }

    @Test func stopInsidePrivatePreparationPropagatesOriginalCancellationWithoutPublication() async throws {
        let models = try TestModelContainer()
        let store = MCPTaskQuerySnapshotStore()
        let coordinator = MCPReadCoordinator(domain: store.domain)
        let service = MCPReadService(source: MCPReadCaptureBuilder(container: models.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil),
            snapshots: store, pagePreparer: { _, tool, operation in
                let page = try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: "[]",
                    isError: nil, origin: .generatedJSON, evidence: .established,
                    context: MCPResultContext(tool: tool, semanticFailure: nil,
                        mutationRecovery: nil, entityPositions: []), metadataOwner: nil)) {
                    guard operation.shouldContinue() else { throw CancellationError() }
                }
                coordinator.stop()
                return [page]
            })
        let output = await coordinator.execute(timeout: Data("stopped".utf8), busy: Data("busy".utf8)) { operation in
            await MainActor.run {
                do {
                    let read = try MCPPreparedToolRead(text: "[]")
                    #expect(throws: CancellationError.self) {
                        try service.preparePrivatePages([read], tool: "query_tasks", operation: operation)
                    }
                } catch { Issue.record("Cancellation fixture setup failed: \(error)") }
                return Self.response(Data("must-not-deliver".utf8))
            }
        }
        #expect(output == Data("stopped".utf8))
        #expect(store.retainedBytes == 0)
        for _ in 0..<100 where coordinator.unfinishedCount != 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test func expiredPublicationSelectsReadyWholeModernFailureAndDiscardsAllOwners() async throws {
        let instant = ContinuousClock.now
        let domain = MCPReadPublicationDomain(testingInstant: instant)
        let store = MCPTaskQuerySnapshotStore(now: { instant }, domain: domain)
        let coordinator = MCPReadCoordinator(domain: domain)
        let errors = try failureBytes("QUERY_EXPIRED")
        let timeout = try failureBytes("READ_TIMEOUT")
        let busy = try failureBytes("READ_BUSY")
        let output = await coordinator.execute(timeout: timeout, busy: busy) { operation in
            await MainActor.run {
                do {
                    let pages = try ["[]", "null"].map { text in
                        try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: text,
                            isError: nil, origin: .generatedJSON, evidence: .established,
                            context: MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                                mutationRecovery: nil, entityPositions: []), metadataOwner: nil))
                    }
                    let bundle = try MCPResultPreparation.prepare(pages: pages, budget: MCPResultRetentionBudget(
                        store: .ordinary, originalCaptureIndexBytes: 0, visibleBytes: 0, pendingBytes: 0))
                    let reservation = try #require(try store.prepare(preparedBundle: bundle,
                        cursors: [UUID().uuidString], deadline: instant + .milliseconds(200),
                        operationID: operation.id, metadataBytes: nil, policy: .cached))
                    let bytes = try MCPResultEncoder.encode(fragment: pages[0].fragment, id: .integer(16))
                    // A root near its original expiry can expire during a still-admitted read.
                    domain.setTestingInstant(instant + .milliseconds(201))
                    #expect(operation.shouldContinue())
                    return PreparedReadResult(encodedResponse: bytes, publications: [reservation],
                        publicationErrors: .init(busy: busy, expired: errors, capacity: errors))
                } catch {
                    Issue.record("Modern offered-page preparation failed: \(error)")
                    return Self.response(Data("failed".utf8))
                }
            }
        }
        #expect(output == errors)
        #expect(output != timeout && output != busy)
        #expect(try domain.accounting(for: store.publicationStoreID).visibleBytes == 0)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        for _ in 0..<100 where coordinator.unfinishedCount != 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(coordinator.unfinishedCount == 0)
    }

    nonisolated private static func response(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }

    private func failureBytes(_ code: String) throws -> Data {
        let source = try MCPResultAdapter.source(text: "{\"error\":{\"code\":\"\(code)\"}}",
            isError: true, origin: .generatedJSON, evidence: .established)
        let context = MCPResultContext(tool: "query_tasks", semanticFailure: nil,
            mutationRecovery: nil, entityPositions: [])
        return try MCPResultEncoder.encode(source: source, presentation: MCPResultAdapter.present(source,
            context: context), id: .integer(16), metadata: nil)
    }

    private enum StorageFault: Error { case unavailable }
}
#endif
