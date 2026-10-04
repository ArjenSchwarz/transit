#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import SwiftData
import Testing
@testable import Transit

/// Combined modern consumer acceptance; common adapters and retained-fragment ownership stay external.
@MainActor @Suite(.serialized)
struct MCPPortfolioModernAcceptanceTests {
    @Test func discoverySchemasAndStatelessValidationRejectBeforeCapture() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let discovery = try await send(env, method: "server/discover")
            let discovered = try result(discovery)
            #expect(discovered["supportedVersions"] as? [String] == ["2026-07-28"])
            #expect(discovered["resultType"] as? String == "complete")
            let listed = try result(try await send(env, method: "tools/list"))
            let tools = try #require(listed["tools"] as? [[String: Any]])
            for name in ["query_project_summaries", "query_tasks"] {
                let tool = try #require(tools.first { $0["name"] as? String == name })
                let output = try #require(tool["outputSchema"] as? [String: Any])
                let properties = try #require(output["properties"] as? [String: Any])
                #expect(properties["contractVersion"] != nil && properties["source"] != nil
                        && properties["presentation"] != nil)
                let required = try #require(output["required"] as? [String])
                #expect(Set(required) == ["contractVersion", "source", "presentation"])
                #expect(output["additionalProperties"] as? Bool == false)
                let version = try #require(properties["contractVersion"] as? [String: Any])
                #expect(version["const"] as? Int == 1)
                #expect(tool["inputSchema"] is [String: Any])
            }
            let valid = try MCPPortfolioModernHTTPHarness.request(tool: "query_project_summaries", arguments: initial)
            let missing = Data("""
                {"jsonrpc":"2.0","id":2382,"method":"tools/call",
                 "params":{"name":"query_project_summaries","arguments":{}}}
                """.utf8)
            let oldVersion = Data(try #require(String(data: valid, encoding: .utf8))
                .replacingOccurrences(of: "2026-07-28", with: "2025-03-26").utf8)
            let cases = [
                Rejected(body: Data("[".utf8) + valid + Data("]".utf8), code: -32600),
                Rejected(body: missing, code: -32602),
                Rejected(body: valid, method: "tools/list", code: -32020),
                Rejected(body: valid, tool: "query_tasks", code: -32020),
                Rejected(body: valid, version: "2025-03-26", code: -32020),
                Rejected(body: oldVersion, version: "2025-03-26", code: -32022)
            ]
            for invalid in cases {
                let rejected = try await MCPPortfolioModernHTTPHarness.post(
                    responder: MCPServer.makeRouter(handler: env.handler).buildResponder(), body: invalid.body,
                    tool: invalid.tool, method: invalid.method, version: invalid.version)
                #expect(rejected.status == .badRequest)
                let envelope = try #require(rejected.json as? [String: Any])
                #expect((envelope["error"] as? [String: Any])?["code"] as? Int == invalid.code)
                #expect(envelope["result"] == nil)
            }
            #expect(env.fetchCount.value == 0)
            let accounting = try env.handler.reusableSnapshots.get().domain.accounting(
                for: env.handler.reusableSnapshots.get().publicationStoreID)
            #expect(accounting.visibleEntries == 0 && accounting.pendingEntries == 0)
        }
    }

    @Test func structuredSourcePreservesLargeDisplayIDAndExactFrozenMetadataBytes() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            env.fixture.tasks[0].permanentDisplayId = 9_007_199_254_740_993
            try env.fixture.owner.context.save()
            let summaryResponse = try await send(env, tool: "query_project_summaries", arguments: initial)
            let summary = try checkedSource(summaryResponse)
            let snapshot = try #require(summary.metadata["snapshotId"] as? String)
            let root = try env.handler.reusableSnapshots.get().retainedView(for: snapshot, now: .now)
            try exactMetadata(summaryResponse, bytes: root.frozenMetadataBytes)
            let response = try await send(env, tool: "query_tasks", arguments: taskArguments(snapshot, limit: 100))
            let source = try checkedSource(response)
            try exactMetadata(response, bytes: root.frozenMetadataBytes)
            let rows = try #require(source.payload["results"] as? [[String: Any]])
            #expect(rows.count == 9 && rows.allSatisfy { $0["comments"] == nil && $0["revision"] is String })
            let values = try array(member("results", source.value))
            let row = try #require(values.first {
                string(member("taskId", $0)) == env.fixture.tasks[0].id.uuidString
            })
            guard case .number(let displayID) = member("displayId", row) else {
                throw MCPResultBoundaryError.unsupportedEvidence
            }
            #expect(displayID.lexeme == "9007199254740993")
            #expect(root.capture.tasks.first { $0.id == env.fixture.tasks[0].id }?.revision
                    == rows.first {
                        $0["taskId"] as? String == env.fixture.tasks[0].id.uuidString
                    }?["revision"] as? String)
        }
    }

    @Test func modernFrozenPagesReconcileAllStatusesAfterSavedMutationWithoutRecapture() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let response = try await send(env, tool: "query_project_summaries", arguments: initial)
            let summary = try checkedSource(response)
            let snapshot = try #require(summary.metadata["snapshotId"] as? String)
            let root = try env.handler.reusableSnapshots.get().retainedView(for: snapshot, now: .now)
            let projects = try #require(summary.payload["projects"] as? [[String: Any]])
            let project = try #require(projects.first {
                $0["projectId"] as? String == MCPPortfolioFixture.populatedProjectID.uuidString
            })
            let counts = try #require(project["countsByStatus"] as? [String: Int])
            env.fixture.tasks[0].statusRawValue = "done"
            env.fixture.comment.content = "Later saved comment"
            try env.fixture.owner.context.save()
            for status in MCPSnapshotTaskQueryRequest.supportedStatuses {
                var arguments = taskArguments(snapshot, limit: 1)
                arguments["status"] = [status]
                var rows: [[String: Any]] = []
                var cursors = Set<String>()
                repeat {
                    let pageResponse = try await send(env, tool: "query_tasks", arguments: arguments)
                    let page = try checkedSource(pageResponse)
                    try exactMetadata(pageResponse, bytes: root.frozenMetadataBytes)
                    #expect(page.payload["expiresAt"] as? String == summary.payload["expiresAt"] as? String)
                    rows += try #require(page.payload["results"] as? [[String: Any]])
                    guard let cursor = page.payload["nextCursor"] as? String else { break }
                    try #require(cursors.insert(cursor).inserted)
                    #expect(MCPCursorFamily.classify(cursor) == .reusable)
                    arguments = ["cursor": cursor]
                } while true
                #expect(rows.count == counts[status] && rows.allSatisfy { $0["status"] as? String == status })
            }
            #expect(env.fetchCount.value == 1)
            let replayResponse = try await send(
                env, tool: "query_project_summaries", arguments: ["snapshotId": snapshot], id: 2383)
            let replay = try checkedSource(replayResponse, id: 2383)
            let sealed = try #require(root.preparedResultPage)
            let expected = try MCPResultEncoder.encode(fragment: sealed.fragment, id: .integer(2383))
            #expect(replayResponse.body == expected)
            #expect(replay.text == summary.text && replay.value == summary.value)
            try exactMetadata(replayResponse, bytes: root.frozenMetadataBytes)
            #expect(env.fetchCount.value == 1)
        }
    }

    @Test func modernOrdinaryV4PagesKeepRawStatusFieldsAndOriginalMetadataAfterSavedChanges() async throws {
        let env = try Environment()
        try await withDrainedEnvironment(env) {
            let firstResponse = try await send(env, tool: "query_tasks", arguments: [
                "detailLevel": "summary", "includeComments": false, "limit": 1, "readPolicy": "cached"])
            let first = try checkedSource(firstResponse)
            var cursor = try #require(first.payload["nextCursor"] as? String)
            #expect(MCPCursorFamily.classify(cursor) == .ordinary)
            let retained = try env.handler.taskQuerySnapshots.retainedPage(for: cursor)
            let metadata = try #require(retained.metadataBytes)
            try exactMetadata(firstResponse, bytes: metadata)
            var rows = try #require(first.payload["results"] as? [[String: Any]])
            env.fixture.tasks[8].statusRawValue = "done"
            try env.fixture.owner.context.save()
            var cursors = Set<String>()
            while true {
                try #require(cursors.insert(cursor).inserted)
                let response = try await send(env, tool: "query_tasks", arguments: ["cursor": cursor])
                let page = try checkedSource(response)
                try exactMetadata(response, bytes: metadata)
                #expect(page.payload["expiresAt"] as? String == first.payload["expiresAt"] as? String)
                rows += try #require(page.payload["results"] as? [[String: Any]])
                guard let next = page.payload["nextCursor"] as? String else { break }
                #expect(MCPCursorFamily.classify(next) == .ordinary)
                cursor = next
            }
            #expect(rows.count == 9 && rows.contains { $0["status"] as? String == "unknown" })
            #expect(rows.allSatisfy { $0["revision"] == nil && $0["description"] == nil && $0["comments"] == nil })
            #expect(env.fetchCount.value == 1)
        }
    }
}

private extension MCPPortfolioModernAcceptanceTests {
    struct Rejected {
        let body: Data
        var method = "tools/call"
        var tool = "query_project_summaries"
        var version = "2026-07-28"
        let code: Int
    }

    @MainActor final class FetchCount { var value = 0 }
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

    struct Source {
        let text: String
        let value: MCPJSONValue
        let payload: [String: Any]
        let metadata: [String: Any]
    }

    var initial: [String: Any] {
        ["start": "2026-10-03T00:00:00Z", "end": "2026-10-03T01:00:00Z", "limit": 100, "readPolicy": "cached"]
    }

    func taskArguments(_ snapshot: String, limit: Int) -> [String: Any] {
        ["snapshotId": snapshot, "detailLevel": "full", "includeComments": false, "limit": limit]
    }

    func send(_ env: Environment, tool: String? = nil, arguments: [String: Any] = [:],
              method: String = "tools/call", id: Int = 2382) async throws -> MCPPortfolioModernHTTPHarness.Response {
        let body = try MCPPortfolioModernHTTPHarness.request(tool: tool, arguments: arguments, method: method, id: id)
        let response = try await MCPPortfolioModernHTTPHarness.post(
            responder: MCPServer.makeRouter(handler: env.handler).buildResponder(),
            body: body, tool: tool, method: method)
        #expect(response.status == .ok && response.elapsed <= .seconds(5))
        return response
    }

    func result(_ response: MCPPortfolioModernHTTPHarness.Response, id: Int = 2382) throws -> [String: Any] {
        let envelope = try #require(response.json as? [String: Any])
        #expect(envelope["id"] as? Int == id && envelope["error"] == nil)
        return try #require(envelope["result"] as? [String: Any])
    }

    func checkedSource(_ response: MCPPortfolioModernHTTPHarness.Response, id: Int = 2382) throws -> Source {
        let result = try result(response, id: id)
        try #require(result["isError"] as? Bool != true)
        #expect(result["resultType"] as? String == "complete")
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.count == 1 && content.first?["type"] as? String == "text")
        let text = try #require(content.first?["text"] as? String)
        let document = try MCPJSONDocument.parse(response.body)
        let structured = member("structuredContent", member("result", document.value))
        guard case .number(let version) = member("contractVersion", structured) else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        #expect(version.lexeme == "1" && string(member("kind", member("source", structured))) == "json")
        let value = try #require(member("payload", member("source", structured)))
        #expect(try value == MCPJSONDocument.parse(text).value)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let metadata = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        return Source(text: text, value: value, payload: payload, metadata: metadata)
    }

    func member(_ name: String, _ value: MCPJSONValue?) -> MCPJSONValue? {
        guard case .object(let fields) = value else { return nil }
        return fields.first { $0.name == name }?.value
    }

    func string(_ value: MCPJSONValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }

    func array(_ value: MCPJSONValue?) throws -> [MCPJSONValue] {
        guard case .array(let values) = value else { throw MCPResultBoundaryError.unsupportedEvidence }
        return values
    }

    func exactMetadata(_ response: MCPPortfolioModernHTTPHarness.Response, bytes: Data) throws {
        let namespace = Data("\"me.nore.ig.transit/read\":".utf8) + bytes
        #expect(response.body.range(of: namespace) != nil, "Retained metadata bytes must be inserted unchanged")
        _ = try MCPJSONDocument.parse(bytes)
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
