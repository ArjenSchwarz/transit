#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

/// Actual router RED, separate from the historical batch transport component fixtures.
@Suite(.serialized)
nonisolated struct MCPBoundedReadRouteTests {
    @MainActor private final class Fixture {
        let owner: TestModelContainer
        let handler: MCPToolHandler
        let service: MCPReadService
        let savedTask: TransitTask
        init(owner: TestModelContainer, handler: MCPToolHandler, service: MCPReadService, savedTask: TransitTask) {
            self.owner = owner; self.handler = handler; self.service = service; self.savedTask = savedTask
        }
    }

    @Test @concurrent func actualRouterReturnsSavedResultAndFullRPCIdentity() async throws {
        let fixture = try await Self.fixture()
        let id = String(repeating: "rpc-id-", count: 128)
        let response = try await MCPTestHelpers.respond(handler: fixture.handler,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: "2026-07-28", body: Self.body(id: id), loggerLabel: "bounded-read-route")
        #expect(response.status == .ok)
        let frame = try #require(response.json as? [String: Any])
        #expect(frame["jsonrpc"] as? String == "2.0" && frame["id"] as? String == id)
        let result = try #require(frame["result"] as? [String: Any])
        let payload = try Self.payload(result)
        let records = try #require(payload["results"] as? [[String: Any]])
        #expect(records.first?["name"] as? String == "Saved task")
        let meta = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(meta["snapshotId"] != nil && meta["asOf"] != nil)
        #expect(frame["_meta"] == nil && frame["content"] == nil)
    }

    @Test @concurrent func actualRouterFreezesCursorMetadataAndPublishesOnlySelectedPage() async throws {
        let fixture = try await Self.fixture(twoTasks: true)
        let first = try await MCPTestHelpers.respond(handler: fixture.handler,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: "2026-07-28", body: Self.body(id: "first"), loggerLabel: "bounded-read-cursor")
        let frame = try #require(first.json as? [String: Any])
        let result = try #require(frame["result"] as? [String: Any])
        let payload = try Self.payload(result)
        let cursor = try #require(payload["nextCursor"] as? String)
        let original = try #require(fixture.service.snapshots.retainedPage(for: cursor).metadataBytes)
        #expect(first.body.range(of: original) != nil)
        await MainActor.run { fixture.savedTask.name = "Changed after capture" }
        let replay = try await MCPTestHelpers.respond(handler: fixture.handler,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: "2026-07-28", body: Self.body(id: "replay", arguments: ["cursor": cursor]),
            loggerLabel: "bounded-read-cursor")
        let replayFrame = try #require(replay.json as? [String: Any])
        let replayResult = try #require(replayFrame["result"] as? [String: Any])
        #expect(replay.body.range(of: original) != nil)
        #expect(replayResult["_meta"] != nil)
        #expect(replayFrame["id"] as? String == "replay")
        #expect(fixture.service.snapshots.domain === fixture.handler.taskQuerySnapshots.domain)
    }

    @Test(arguments: [false, true]) @concurrent
    func actualRouterDeadlineCoversValidAndInvalidToolArguments(invalid: Bool) async throws {
        let fixture = try await Self.fixture()
        let started = DispatchSemaphore(value: 0)
        let blocker = Task { @MainActor in Self.blockMainActor(started) }
        Self.waitForStart(started)
        let start = ContinuousClock.now
        var args: [String: Any] = ["detailLevel": "summary", "includeComments": false, "limit": 1]
        if invalid { args["status"] = true }
        let response: MCPHTTPTestResponse
        do {
            response = try await MCPTestHelpers.respond(handler: fixture.handler,
                contentType: "application/json", accept: "application/json, text/event-stream",
                protocolVersion: "2026-07-28", body: Self.body(id: "bounded", arguments: args),
                loggerLabel: "bounded-read-deadline")
        } catch {
            await blocker.value
            throw error
        }
        let elapsed = start.duration(to: .now)
        print("T63_ROUTE invalid_tool_arguments=\(invalid) encoded_body_elapsed=\(elapsed)")
        #expect(elapsed < .seconds(5))
        await blocker.value
        let frame = try #require(response.json as? [String: Any])
        #expect(frame["id"] as? String == "bounded")
        let result = try #require(frame["result"] as? [String: Any])
        let meta = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(meta["category"] as? String == "timeout")
        #expect(meta["snapshotId"] == nil && meta["asOf"] == nil)
    }

    @MainActor private static func blockMainActor(_ signal: DispatchSemaphore) {
        signal.signal()
        Thread.sleep(forTimeInterval: 6)
    }

    private static func waitForStart(_ signal: DispatchSemaphore) { signal.wait() }

    @MainActor private static func fixture(twoTasks: Bool = false) throws -> Fixture {
        let owner = try TestModelContainer()
        owner.context.autosaveEnabled = false
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Saved task", type: .feature, project: project, displayID: .permanent(1))
        owner.context.insert(project)
        owner.context.insert(task)
        if twoTasks {
            owner.context.insert(TransitTask(name: "Second saved task", type: .feature,
                                             project: project, displayID: .permanent(2)))
        }
        try owner.context.save()
        task.name = "Unsaved UI task"
        let tasks = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestones = DisplayIDAllocator(store: InMemoryCounterStore())
        let comments = CommentService(modelContext: owner.context)
        let store = MCPTaskQuerySnapshotStore()
        let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
        let service = MCPReadService(source: builder,
            monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil), snapshots: store)
        let handler = MCPToolHandler(taskService: TaskService(modelContext: owner.context, displayIDAllocator: tasks),
            projectService: ProjectService(modelContext: owner.context), commentService: comments,
            milestoneService: MilestoneService(modelContext: owner.context, displayIDAllocator: milestones),
            maintenanceService: DisplayIDMaintenanceService(modelContext: owner.context, taskAllocator: tasks,
                milestoneAllocator: milestones, commentService: comments), settings: MCPSettings(),
            taskQuerySnapshots: store, readService: service)
        return Fixture(owner: owner, handler: handler, service: service, savedTask: task)
    }

    private static func body(id: String, arguments: [String: Any]? = nil) throws -> String {
        let args = arguments ?? ["detailLevel": "summary", "includeComments": false, "limit": 1]
        let bytes = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id,
            "method": "tools/call", "params": ["name": "query_tasks", "arguments": args]])
        return try #require(String(data: bytes, encoding: .utf8))
    }

    private static func payload(_ result: [String: Any]) throws -> [String: Any] {
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

}
#endif
