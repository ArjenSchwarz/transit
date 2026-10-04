#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
import SwiftData
import Testing
@testable import Transit

/// Real individual POSTs; coordinator stop/start is not a full MCPServer restart assertion.
@Suite(.serialized)
nonisolated struct MCPPortfolioRouterDeadlineTests {
    @Test @concurrent func blockedRegisteredSummaryReturnsTimeoutBeforePhysicalCaptureFinishes() async throws {
        try await Self.withPrepared { prepared in
            let response = try await Self.post(prepared, id: 2382)
            try Self.failure(response, code: "READ_TIMEOUT")
            #expect(prepared.latch.started && !prepared.latch.finished)
            #expect(prepared.coordinator.unfinishedCount == 1)
            let accounting = try prepared.store.domain.accounting(for: prepared.store.publicationStoreID)
            #expect(accounting.visibleEntries == 0 && accounting.pendingEntries == 0)
        }
    }

    @Test @concurrent func eightActualPostsRetainPhysicalChargeAcrossCoordinatorRestartAndNinthIsBusy() async throws {
        try await Self.withPrepared { prepared in
            let responses = try await withThrowingTaskGroup(of: WireResponse.self) { group in
                for id in 1...8 { group.addTask { try await Self.post(prepared, id: id) } }
                var results: [WireResponse] = []
                for try await response in group { results.append(response) }
                return results
            }
            #expect(responses.count == 8 && Set(responses.map(\.id)).count == 8)
            var requestIDs = Set<String>()
            for response in responses { requestIDs.insert(try Self.failure(response, code: "READ_TIMEOUT")) }
            #expect(requestIDs.count == 8)
            #expect(prepared.latch.started && !prepared.latch.finished)
            #expect(prepared.coordinator.unfinishedCount == 8)
            prepared.coordinator.stop()
            prepared.coordinator.start()
            #expect(prepared.coordinator.unfinishedCount == 8)
            try Self.failure(try await Self.post(prepared, id: 9), code: "READ_BUSY")
            #expect(prepared.coordinator.unfinishedCount == 8)
        }
    }
}

private extension MCPPortfolioRouterDeadlineTests {
    struct Prepared: Sendable {
        let owner: Owner
        let responder: RouterResponder<MCPRequestContext>
        let coordinator: MCPReadCoordinator
        let store: MCPReusableSnapshotStore
        let latch: CaptureLatch
    }

    struct LatchSnapshot {
        let released: Bool
        let entries: Int
        let completions: Int
        let expirations: Int
    }

    final class CaptureLatch: @unchecked Sendable {
        private let condition = NSCondition()
        private var released = false
        private var entries = 0
        private var completions = 0
        private var failSafeExpirations = 0
        private var snapshot: LatchSnapshot {
            condition.lock()
            defer { condition.unlock() }
            return LatchSnapshot(released: released, entries: entries, completions: completions,
                            expirations: failSafeExpirations)
        }
        var started: Bool { snapshot.entries > 0 }
        var finished: Bool { let value = snapshot; return value.entries > 0 && value.completions == value.entries }
        var explicitlyReleased: Bool { let value = snapshot; return value.released && value.expirations == 0 }
        var entryCount: Int { snapshot.entries }
        var completionCount: Int { snapshot.completions }
        func block() {
            condition.lock()
            entries += 1
            let deadline = ContinuousClock.now.advanced(by: .seconds(12))
            while !released && ContinuousClock.now < deadline {
                _ = condition.wait(until: Date().addingTimeInterval(0.1))
            }
            if !released { failSafeExpirations += 1 }
            completions += 1
            condition.unlock()
        }
        func unblock() {
            condition.lock()
            released = true
            condition.broadcast() // Idempotent release also lets unexpected later entries return immediately.
            condition.unlock()
        }
    }

    @MainActor final class Owner {
        let fixture: MCPPortfolioSavedFixture
        let handler: MCPToolHandler

        init(latch: CaptureLatch) throws {
            fixture = try MCPPortfolioSavedFixture()
            let context = fixture.owner.context
            let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
            let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
            let tasks = TaskService(modelContext: context, displayIDAllocator: taskAllocator)
            let projects = ProjectService(modelContext: context)
            let comments = CommentService(modelContext: context)
            let milestones = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)
            let maintenance = DisplayIDMaintenanceService(modelContext: context, taskAllocator: taskAllocator,
                milestoneAllocator: milestoneAllocator, commentService: comments)
            let domain = MCPReadPublicationDomain()
            let snapshots = MCPTaskQuerySnapshotStore(domain: domain)
            let service = MCPReadService(source: MCPReadCaptureBuilder(container: fixture.owner.container,
                fence: .actorOnlyTestFixture, fetchTasks: { context in
                    latch.block()
                    return try context.fetch(FetchDescriptor<TransitTask>())
                }),
                monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil),
                snapshots: snapshots, pagePreparer: {
                    try MCPModernProviderBinding.prepareReadPages($0, tool: $1, operation: $2)
                })
            handler = MCPToolHandler(taskService: tasks, projectService: projects, commentService: comments,
                milestoneService: milestones, maintenanceService: maintenance, settings: MCPSettings(),
                persistence: FallbackOutcomeFixture.makeHealthy(), taskQuerySnapshots: snapshots,
                readService: service, readCoordinator: MCPReadCoordinator(domain: domain))
        }
    }

    struct WireResponse: Sendable {
        let id: Int
        let bytes: Data
        let elapsed: Duration
    }

    @MainActor static func prepare() throws -> Prepared {
        let latch = CaptureLatch()
        let owner = try Owner(latch: latch)
        return Prepared(owner: owner, responder: MCPServer.makeRouter(handler: owner.handler).buildResponder(),
            coordinator: owner.handler.readCoordinator, store: try owner.handler.reusableSnapshots.get(), latch: latch)
    }

    @concurrent static func post(_ prepared: Prepared, id: Int) async throws -> WireResponse {
        let body = try MCPPortfolioModernHTTPHarness.request(tool: "query_project_summaries", arguments: [
            "start": "2026-10-03T00:00:00Z", "end": "2026-10-03T01:00:00Z", "limit": 100,
            "readPolicy": "cached"], id: id)
        let response = try await MCPPortfolioModernHTTPHarness.post(
            responder: prepared.responder, body: body, tool: "query_project_summaries")
        #expect(response.status == .ok && response.elapsed <= .seconds(5))
        return WireResponse(id: id, bytes: response.body, elapsed: response.elapsed)
    }

    @discardableResult static func failure(_ response: WireResponse, code: String) throws -> String {
        let envelope = try #require(try JSONSerialization.jsonObject(with: response.bytes) as? [String: Any])
        #expect(envelope["id"] as? Int == response.id && envelope["error"] == nil)
        let result = try #require(envelope["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true && result["resultType"] as? String == "complete")
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((payload["error"] as? [String: Any])?["code"] as? String == code)
        let wireValue = try MCPJSONDocument.parse(response.bytes).value
        guard case .object(let root) = wireValue,
              case .object(let toolResult) = root.first(where: { $0.name == "result" })?.value,
              case .object(let structured) = toolResult.first(where: { $0.name == "structuredContent" })?.value,
              case .object(let source) = structured.first(where: { $0.name == "source" })?.value else {
            Issue.record("Missing modern source wrapper")
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        #expect(try source.first(where: { $0.name == "payload" })?.value == MCPJSONDocument.parse(text).value)
        #expect(payload["snapshotId"] == nil && payload["nextCursor"] == nil && payload["projects"] == nil)
        let metadata = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(metadata["category"] as? String == code)
        #expect(metadata["snapshotId"] == nil && metadata["asOf"] == nil && metadata["freshness"] == nil)
        let read = try #require(metadata["read"] as? [String: Any])
        #expect(read["policy"] as? String == "cached" && read["budgetMs"] as? Int == 5_000)
        let requestID = try #require(metadata["requestId"] as? String)
        #expect(UUID(uuidString: requestID) != nil)
        return requestID
    }

    @concurrent static func withPrepared(_ body: @Sendable (Prepared) async throws -> Void) async throws {
        let prepared = try await prepare()
        do {
            try await body(prepared)
            await cleanup(prepared)
        } catch {
            await cleanup(prepared)
            throw error
        }
    }

    @concurrent static func cleanup(_ prepared: Prepared) async {
        prepared.latch.unblock() // Always release before any actor hop, including assertion/parser throws.
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while prepared.coordinator.unfinishedCount != 0 && ContinuousClock.now < deadline {
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
        }
        #expect(prepared.coordinator.unfinishedCount == 0)
        #expect(prepared.latch.finished && prepared.latch.explicitlyReleased)
        #expect(prepared.latch.entryCount == 1 && prepared.latch.completionCount == 1)
        do {
            let accounting = try prepared.store.domain.accounting(for: prepared.store.publicationStoreID)
            #expect(accounting.visibleEntries == 0 && accounting.visibleBytes == 0)
            #expect(accounting.pendingEntries == 0 && accounting.pendingBytes == 0)
        } catch { Issue.record("Could not inspect drained publication accounting: \(error)") }
        withExtendedLifetime(prepared.owner) {}
    }
}
#endif
