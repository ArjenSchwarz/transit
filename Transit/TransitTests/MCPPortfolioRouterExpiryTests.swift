#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import SwiftData
import Testing
@testable import Transit

/// Retention clock boundaries through real registered single-object router requests.
@MainActor @Suite(.serialized)
struct MCPPortfolioRouterExpiryTests {
    @Test func summaryReplayKeepsOriginalExpiryUntilExactDeadline() async throws {
        try await verifyBoundary(cursorMode: false)
    }

    @Test func publishedTaskCursorKeepsOriginalExpiryUntilExactDeadline() async throws {
        try await verifyBoundary(cursorMode: true)
    }
}

private extension MCPPortfolioRouterExpiryTests {
    @MainActor final class FetchCount { var value = 0 }

    func verifyBoundary(cursorMode: Bool) async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let summary = try success(try await request(env, tool: "query_project_summaries", arguments: initial))
            let snapshot = try #require(summary.metadata["snapshotId"] as? String)
            let first = try success(try await request(
                env, tool: "query_tasks", arguments: taskArguments(snapshot, limit: 1)))
            let cursor = try #require(first.payload["nextCursor"] as? String)
            let tool = cursorMode ? "query_tasks" : "query_project_summaries"
            let arguments: [String: Any] = cursorMode ? ["cursor": cursor] : ["snapshotId": snapshot]
            let original = try success(try await request(env, tool: tool, arguments: arguments))
            let expiry = try #require(original.payload["expiresAt"] as? String)
            #expect(first.payload["expiresAt"] as? String == expiry)
            #expect(try canonical(original.metadata) == canonical(summary.metadata))
            let store = try env.handler.reusableSnapshots.get()
            let root = try store.retainedView(for: snapshot, now: .now)
            #expect(root.capture.createdAt.duration(to: root.capture.retentionDeadline) == .seconds(300))
            let fetches = env.fetchCount.value
            #expect(fetches == 1)
            // These are pin-only reads of existing bytes, never new projection/reservation at a future clock.
            store.domain.setTestingInstant(root.capture.retentionDeadline - .milliseconds(1))
            let near = try success(try await request(env, tool: tool, arguments: arguments))
            #expect(try canonical(near.payload) == canonical(original.payload))
            #expect(try canonical(near.metadata) == canonical(original.metadata))
            #expect(near.payload["expiresAt"] as? String == expiry)
            #expect(env.fetchCount.value == fetches)
            await drain(env)
            let before = try store.domain.accounting(for: store.publicationStoreID)
            store.domain.setTestingInstant(root.capture.retentionDeadline)
            let expired = try await request(env, tool: tool, arguments: arguments)
            try expectFamilyError(expired, code: cursorMode ? "INVALID_CURSOR" : "INVALID_SNAPSHOT")
            #expect(env.fetchCount.value == fetches)
            await drain(env)
            let after = try store.domain.accounting(for: store.publicationStoreID)
            #expect(after.pendingEntries == 0 && after.pendingBytes == 0)
            #expect(after.visibleEntries <= before.visibleEntries && after.visibleBytes <= before.visibleBytes)
        }
    }

    func expectFamilyError(_ result: [String: Any], code: String) throws {
        #expect(result["isError"] as? Bool == true)
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((payload["error"] as? [String: Any])?["code"] as? String == code)
        #expect(payload["snapshotId"] == nil && payload["nextCursor"] == nil && payload["results"] == nil)
        let metadata = (result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any]
        #expect(metadata?["snapshotId"] == nil && metadata?["asOf"] == nil && metadata?["freshness"] == nil)
    }

    @MainActor struct Environment {
        let fixture: MCPPortfolioSavedFixture
        let handler: MCPToolHandler
        let fetchCount: FetchCount

        init(taskCount: Int = 9, commentOnEveryTask: Bool = false) throws {
            fixture = try MCPPortfolioSavedFixture(taskCount: taskCount, commentOnEveryTask: commentOnEveryTask)
            let counter = FetchCount()
            fetchCount = counter
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
                    counter.value += 1
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

    struct Result {
        let payload: [String: Any]
        let metadata: [String: Any]
    }

    var initial: [String: Any] {
        ["start": "2026-10-03T00:00:00Z", "end": "2026-10-03T01:00:00Z", "limit": 100, "readPolicy": "cached"]
    }

    func taskArguments(_ snapshot: String, limit: Int) -> [String: Any] {
        ["snapshotId": snapshot, "detailLevel": "full", "includeComments": false, "limit": limit]
    }

    func request(_ env: Environment, tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        let body = try MCPPortfolioModernHTTPHarness.request(tool: tool, arguments: arguments)
        let response = try await MCPPortfolioModernHTTPHarness.post(
            responder: MCPServer.makeRouter(handler: env.handler).buildResponder(), body: body, tool: tool)
        #expect(response.elapsed <= .seconds(5))
        #expect(response.status == .ok)
        let envelope = try #require(response.json as? [String: Any])
        #expect(envelope["id"] as? Int == 2382 && envelope["error"] == nil)
        let result = try #require(envelope["result"] as? [String: Any])
        #expect(result["resultType"] as? String == "complete" && result["structuredContent"] is [String: Any])
        return result
    }

    func success(_ result: [String: Any]) throws -> Result {
        try #require(result["isError"] as? Bool != true)
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let metadata = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        return Result(payload: payload, metadata: metadata)
    }

    func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    func withDrainedEnvironment(_ env: Environment, body: () async throws -> Void) async throws {
        do {
            try await body()
            await drain(env)
        } catch {
            await drain(env)
            throw error
        }
    }

    func drain(_ env: Environment) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while env.handler.readCoordinator.unfinishedCount != 0 && ContinuousClock.now < deadline {
            // Independent sleep still waits when the test task has been cancelled.
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
        }
        #expect(env.handler.readCoordinator.unfinishedCount == 0, "Physical workers must drain before fixture release")
        withExtendedLifetime(env.fixture) {}
    }
}
#endif
