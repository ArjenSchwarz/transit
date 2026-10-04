#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import SwiftData
import Testing
@testable import Transit

/// Actual router/body-writer acceptance preparation. Final API-15 transport negotiation remains separate.
@MainActor @Suite(.serialized)
struct MCPPortfolioIntegrationTests {
    @Test func routerCaptureExcludesPendingEditsWithoutSavingThem() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let captured = try env.fixture.capture()
            env.fixture.project.name = "Unsaved project"
            env.fixture.tasks[0].taskDescription = "Unsaved description"
            env.fixture.comment.content = "Unsaved comment"
            let summary = try success(try await request(env, tool: "query_project_summaries", arguments: initial))
            let projects = try #require(summary.payload["projects"] as? [[String: Any]])
            #expect(projects.contains { $0["name"] as? String == "Populated" })
            #expect(!projects.contains { $0["name"] as? String == "Unsaved project" })
            let snapshot = try #require(summary.metadata["snapshotId"] as? String)
            let rows = try #require(try await taskPages(
                env, snapshot: snapshot, metadata: summary.metadata, limit: 100))
            let row = try #require(rows.first { $0["taskId"] as? String == env.fixture.tasks[0].id.uuidString })
            #expect(row["revision"] as? String == captured.tasks.first { $0.id == env.fixture.tasks[0].id }?.revision)
            #expect(row["description"] as? String != "Unsaved description")
            #expect(env.fixture.owner.context.hasChanges)
            #expect(env.fixture.tasks[0].taskDescription == "Unsaved description")
            #expect(env.fixture.project.name == "Unsaved project" && env.fixture.comment.content == "Unsaved comment")
        }
    }

    @Test func routerPagesReconcileEveryEffectiveStatusAndFreezeCanonicalRecordsAfterSavedChanges() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let capture = try env.fixture.capture()
            let summary = try success(try await request(env, tool: "query_project_summaries", arguments: initial))
            let snapshot = try #require(summary.metadata["snapshotId"] as? String)
            let original = try #require(try await taskPages(
                env, snapshot: snapshot, metadata: summary.metadata, limit: 2))
            try reconcile(summary, rows: original, expected: capture)
            env.fixture.tasks[0].statusRawValue = "done"
            env.fixture.tasks[0].taskDescription = "Saved changed body"
            env.fixture.comment.content = "Saved changed comment"
            try env.fixture.owner.context.save()
            let replay = try success(try await request(
                env, tool: "query_project_summaries", arguments: ["snapshotId": snapshot]))
            #expect(try canonical(replay.payload) == canonical(summary.payload))
            #expect(try canonical(replay.metadata) == canonical(summary.metadata))
            let frozen = try #require(try await taskPages(
                env, snapshot: snapshot, metadata: summary.metadata, limit: 2))
            #expect(try canonical(frozen) == canonical(original))
        }
    }

    @Test func admissionLifecycleInvalidatesPublishedRootAndCursorWithoutAppendPublication() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let summary = try success(try await request(env, tool: "query_project_summaries", arguments: initial))
            let snapshot = try #require(summary.metadata["snapshotId"] as? String)
            let page = try success(try await request(
                env, tool: "query_tasks", arguments: taskArguments(snapshot, limit: 1)))
            let cursor = try #require(page.payload["nextCursor"] as? String)
            env.handler.setTaskQueryAdmission(open: false)
            env.handler.setTaskQueryAdmission(open: false)
            try expectError(try await request(
                env, tool: "query_project_summaries", arguments: ["snapshotId": snapshot]),
                            code: "INVALID_SNAPSHOT")
            try expectError(try await request(env, tool: "query_tasks", arguments: ["cursor": cursor]),
                            code: "INVALID_CURSOR")
            let store = try env.handler.reusableSnapshots.get()
            let accounting = try store.domain.accounting(for: store.publicationStoreID)
            #expect(accounting.visibleEntries == 0 && accounting.pendingEntries == 0 && accounting.pendingBytes == 0)
        }
    }

    @Test func router2375CommentCoveredTasksReturnsCompleteSummaryAndReconciledPagesOrTypedFailure() async throws {
        let env = try Environment(taskCount: 2_375, commentOnEveryTask: true)
        try await withDrainedEnvironment(env) {
            let capture = try env.fixture.capture()
            let result = try await request(env, tool: "query_project_summaries", arguments: initial)
            if result["isError"] as? Bool == true {
                try expectVolumeFailure(result)
            } else {
                let summary = try success(result)
                let snapshot = try #require(summary.metadata["snapshotId"] as? String)
                if let rows = try await taskPages(
                    env, snapshot: snapshot, metadata: summary.metadata, limit: 100, allowVolumeFailure: true
                ) {
                    try reconcile(summary, rows: rows, expected: capture)
                    #expect(rows.count == 2_375)
                }
            }
            await drain(env)
            let store = try env.handler.reusableSnapshots.get()
            let accounting = try store.domain.accounting(for: store.publicationStoreID)
            #expect(accounting.pendingEntries == 0 && accounting.pendingBytes == 0)
            if result["isError"] as? Bool == true { #expect(accounting.visibleEntries == 0) }
        }
    }
}

private extension MCPPortfolioIntegrationTests {
    @MainActor struct Environment {
        let fixture: MCPPortfolioSavedFixture
        let handler: MCPToolHandler

        init(taskCount: Int = 9, commentOnEveryTask: Bool = false) throws {
            fixture = try MCPPortfolioSavedFixture(taskCount: taskCount, commentOnEveryTask: commentOnEveryTask)
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
                fence: .actorOnlyTestFixture),
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

    func taskPages(
        _ env: Environment, snapshot: String, metadata: [String: Any], limit: Int, allowVolumeFailure: Bool = false
    ) async throws -> [[String: Any]]? {
        var arguments = taskArguments(snapshot, limit: limit)
        var rows: [[String: Any]] = []
        var cursors = Set<String>()
        var expiresAt: String?
        repeat {
            let result = try await request(env, tool: "query_tasks", arguments: arguments)
            if allowVolumeFailure && result["isError"] as? Bool == true {
                try expectVolumeFailure(result)
                return nil // No partial page set is asserted as complete reconciliation.
            }
            let page = try success(result)
            #expect(try canonical(page.metadata) == canonical(metadata))
            let expiry = try #require(page.payload["expiresAt"] as? String)
            if let expiresAt { #expect(expiry == expiresAt) } else { expiresAt = expiry }
            rows += try #require(page.payload["results"] as? [[String: Any]])
            guard let cursor = page.payload["nextCursor"] as? String else {
                #expect(page.payload["nextCursor"] is NSNull)
                break
            }
            try #require(cursors.insert(cursor).inserted, "Continuation must make progress")
            arguments = ["cursor": cursor]
        } while true
        return rows
    }

    func reconcile(_ summary: Result, rows: [[String: Any]], expected: CapturedReadView) throws {
        let projects = try #require(summary.payload["projects"] as? [[String: Any]])
        let project = try #require(projects.first {
            $0["projectId"] as? String == MCPPortfolioFixture.populatedProjectID.uuidString
        })
        let counts = try #require(project["countsByStatus"] as? [String: Int])
        #expect(project["totalTaskCount"] as? Int == expected.tasks.count && rows.count == expected.tasks.count)
        for status in MCPSnapshotTaskQueryRequest.supportedStatuses {
            #expect(counts[status] == expected.tasks.filter { $0.effectiveStatus == status }.count)
            #expect(counts[status] == rows.filter { $0["status"] as? String == status }.count)
        }
        #expect(Set(rows.compactMap { $0["taskId"] as? String }).count == rows.count)
        for task in expected.tasks {
            let row = try #require(rows.first { $0["taskId"] as? String == task.id.uuidString })
            #expect(row["revision"] as? String == task.revision && row["comments"] == nil)
            #expect(row["description"] as? String == task.taskDescription)
        }
    }

    func expectError(_ result: [String: Any], code: String) throws {
        #expect(result["isError"] as? Bool == true)
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((payload["error"] as? [String: Any])?["code"] as? String == code)
    }

    func expectVolumeFailure(_ result: [String: Any]) throws {
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let code = try #require((payload["error"] as? [String: Any])?["code"] as? String)
        #expect(["READ_TIMEOUT", "QUERY_CAPACITY_EXCEEDED"].contains(code))
        #expect(payload["projects"] == nil && payload["results"] == nil && payload["nextCursor"] == nil)
        let read = (result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any]
        if code == "READ_TIMEOUT" {
            #expect(read?["category"] as? String == "READ_TIMEOUT")
            #expect(read?["requestId"] is String && read?["read"] is [String: Any])
        }
        // Owner capacity errors carry no invented capture evidence; timeout metadata is failure evidence only.
        #expect(read?["snapshotId"] == nil && read?["asOf"] == nil && read?["freshness"] == nil)
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
