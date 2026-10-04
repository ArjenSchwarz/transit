#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadCallerContractTests {
    private var initial: [String: Any] { ["detailLevel": "summary", "includeComments": false, "limit": 1] }

    @Test func newQueryCreatesCaptureWhileCursorRetainsExactMetadata() async throws {
        let fixture = try MCPReadContractFixture()
        let first = try await fixture.execute(arguments: initial)
        await fixture.drain()
        let payload = try MCPReadContractFixture.payload(first)
        let cursor = try #require(payload["nextCursor"] as? String)
        let retained = try fixture.store.retainedPage(for: cursor)
        let original = try #require(retained.metadataBytes)
        fixture.source.failure = .storageFailure
        let replay = try await fixture.execute(arguments: ["cursor": cursor])
        await fixture.drain()
        #expect(try fixture.store.retainedPage(for: cursor).metadataBytes == original)
        #expect(try MCPReadContractFixture.metadata(replay)["snapshotId"] as? String
            == MCPReadContractFixture.metadata(first)["snapshotId"] as? String)
        #expect(fixture.source.calls == 1)
        fixture.source.failure = nil
        let fresh = try await fixture.execute(arguments: initial)
        await fixture.drain()
        #expect(fixture.source.calls == 2)
        #expect(try MCPReadContractFixture.metadata(fresh)["snapshotId"] as? String
            != MCPReadContractFixture.metadata(first)["snapshotId"] as? String)
    }

    @Test(arguments: 0..<4)
    func cachedAndDefaultPoliciesDoNotInventImportProof(mode: Int) async throws {
        let active = mode < 2
        let cached = mode % 2 == 0
        let fixture = try MCPReadContractFixture(syncActive: active)
        var arguments = initial
        if cached { arguments["readPolicy"] = "cached" }
        let bytes = try await fixture.execute(arguments: arguments)
        await fixture.drain()
        let metadata = try MCPReadContractFixture.metadata(bytes)
        let freshness = try #require(metadata["freshness"] as? [String: Any])
        let read = try #require(metadata["read"] as? [String: Any])
        #expect(read["policy"] as? String == (cached ? "cached" : "refresh_if_needed"))
        #expect(read["refreshOutcome"] as? String == (active && !cached ? "unavailable" : "not_requested"))
        #expect(freshness["assessment"] as? String == (active ? "unknown" : "not_applicable"))
        #expect(freshness["lastImportedAt"] is NSNull)
        #expect(freshness["evidence"] as? String == "none")
        #expect(metadata["asOf"] as? String == freshness["assessedAt"] as? String)
        #expect(fixture.source.calls == 1)
    }

    @Test func failingCaptureHasOneAttemptAndRequiresExplicitRetry() async throws {
        let fixture = try MCPReadContractFixture()
        fixture.source.failure = .storageFailure
        let failed = try await fixture.execute(arguments: initial)
        await fixture.drain()
        let payload = try MCPReadContractFixture.payload(failed)
        #expect((payload["error"] as? [String: Any])?["code"] as? String == "QUERY_FAILED")
        #expect(fixture.source.calls == 1)
        let metadata = try MCPReadContractFixture.metadata(failed)
        #expect(metadata["category"] as? String == "storage_failure")
        #expect(metadata["snapshotId"] == nil && metadata["asOf"] == nil)
        fixture.source.failure = nil
        let retry = try await fixture.execute(arguments: initial)
        await fixture.drain()
        #expect(try MCPReadContractFixture.result(retry)["isError"] as? Bool != true)
        #expect(fixture.source.calls == 2)
    }

    @Test func timedOutPhysicalWorkRequiresBackoffBeforeExplicitRetry() async throws {
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(30), maxOperations: 1)
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let originalID = UUID()
        let timeout = try MCPReadContractFixture.failure("READ_TIMEOUT", id: originalID)
        let busy = try MCPReadContractFixture.failure("READ_BUSY", id: originalID)
        let call = Task.detached {
            await coordinator.execute(timeout: timeout, busy: busy,
                admission: MCPReadAdmission(operationID: originalID), diagnosticTool: "query_tasks") { _ in
                started.signal()
                let gate = await Task.detached { MCPReadContractFixture.wait(release, seconds: 2) }.value
                #expect(gate == .success)
                return Self.prepared(Data("late-success".utf8))
            }
        }
        let began = await Task.detached { MCPReadContractFixture.wait(started, seconds: 1) }.value
        #expect(began == .success)
        let response = await call.value
        #expect(response == timeout && coordinator.unfinishedCount == 1)
        let refused = await coordinator.execute(timeout: timeout, busy: busy) { _ in
            Issue.record("Busy call started another physical attempt")
            return Self.prepared(Data())
        }
        #expect(refused == busy)
        // The caller waits for capacity recovery, rather than spinning automatic read attempts.
        release.signal()
        let drainDeadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < drainDeadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
        let retried = await coordinator.execute(timeout: timeout, busy: busy) { _ in
            Self.prepared(Data("explicit-retry".utf8))
        }
        #expect(retried == Data("explicit-retry".utf8))
        let finalDeadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < finalDeadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test func advertisedReadDescriptionsExplainPolicyEvidenceAndRetryBoundary() {
        let tools = [MCPToolDefinitions.queryTasks, MCPToolDefinitions.getProjects, MCPToolDefinitions.queryMilestones]
        for tool in tools {
            #expect(tool.description.contains("refresh_if_needed"))
            #expect(tool.description.contains("cached"))
            #expect(tool.description.contains("unknown"))
            #expect(tool.description.contains("five seconds"))
            #expect(tool.description.contains("backoff"))
            #expect(tool.description.contains("READ_BUSY") && tool.description.contains("READ_TIMEOUT"))
        }
        #expect(MCPToolDefinitions.queryTasks.description.contains("new capture"))
        #expect(MCPToolDefinitions.queryTasks.description.contains("cursor"))
        #expect(MCPToolDefinitions.queryTasks.description.contains("automatic retry"))
    }

    nonisolated private static func prepared(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
                           publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }
}
#endif
