#if os(macOS)
import Foundation
import HTTPTypes
import NIOConcurrencyHelpers
import Testing
@testable import Transit

/// Modern request registrations; IDs correlate messages and never group concurrent streams.
@MainActor @Suite(.serialized)
struct MCPToolListChangeNotificationTests {
    @Test func burstBeforeConsumptionNeverEvictsAcknowledgementAndCoalescesChanges() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let original = env.mcpSettings.maintenanceToolsEnabled
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler, id: "burst")
        do {
            try requireStream(stream)
            for _ in 0..<512 { env.mcpSettings.maintenanceToolsEnabled.toggle() }
            stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count >= 2 })
            let messages = try stream.messages()
            try #require(messages.count == 2)
            #expect(messages.count == 2, "512 queued invalidations coalesce to one after the protected ack")
            try assertAck(messages[0], id: "burst", accepted: ["toolsListChanged": true])
            try assertChange(messages[1], id: "burst")
            env.mcpSettings.maintenanceToolsEnabled.toggle()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 3 })
            try assertChange(try stream.messages()[2], id: "burst")
        } catch {
            await stream.close(); env.mcpSettings.maintenanceToolsEnabled = original; throw error
        }
        await stream.close(); env.mcpSettings.maintenanceToolsEnabled = original
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test func parallelStringIntegerAndRepeatedIDsOwnIndependentFilteredStreams() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let original = env.mcpSettings.maintenanceToolsEnabled
        var streams: [MCPSubscriptionFixture] = []
        let ids: [Any] = ["17", 17, "17"]
        do {
            for id in ids {
                let stream = try await MCPSubscriptionFixture.open(handler: env.handler, id: id)
                streams.append(stream); try requireStream(stream); stream.startBody()
            }
            try #require(await MCPSubscriptionFixture.wait { env.handler.activeToolListChangeStreamCount == 3 })
            env.mcpSettings.maintenanceToolsEnabled.toggle()
            for (index, stream) in streams.enumerated() {
                try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 2 })
                let messages = try stream.messages()
                try assertAck(messages[0], id: ids[index], accepted: ["toolsListChanged": true])
                try assertChange(messages[1], id: ids[index])
            }
        } catch {
            for stream in streams { await stream.close() }
            env.mcpSettings.maintenanceToolsEnabled = original; throw error
        }
        for stream in streams { await stream.close() }
        env.mcpSettings.maintenanceToolsEnabled = original
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test(arguments: [0, 1, 2])
    func unsupportedEmptyAndFalseFiltersNeverOptIntoNotifications(variant: Int) async throws {
        let filters: [[String: Any]] = [[:], ["toolsListChanged": false],
            ["promptsListChanged": true, "resourcesListChanged": true, "resourceSubscriptions": ["fixture://only"]]]
        let env = try MCPTestHelpers.makeEnv()
        let original = env.mcpSettings.maintenanceToolsEnabled
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler, filters: filters[variant])
        do {
            try requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            try assertAck(try stream.messages()[0], id: 7, accepted: [:])
            env.mcpSettings.maintenanceToolsEnabled.toggle()
            env.handler.finishToolListChangeSessions()
            try #require(await MCPSubscriptionFixture.wait { stream.writer.finished.withLockedValue { $0 } })
            let messages = try stream.messages()
            #expect(messages.count == 2)
            try assertComplete(messages[1], id: 7)
        } catch { await stream.close(); env.mcpSettings.maintenanceToolsEnabled = original; throw error }
        await stream.close(); env.mcpSettings.maintenanceToolsEnabled = original
    }

    @Test func supportedSubsetOnlyAndSameValueAssignmentDoesNotInvalidate() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler,
            filters: ["toolsListChanged": true, "promptsListChanged": true, "extension": ["unknown": true]])
        do {
            try requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            try assertAck(try stream.messages()[0], id: 7, accepted: ["toolsListChanged": true])
            let unchanged = env.mcpSettings.maintenanceToolsEnabled
            env.mcpSettings.maintenanceToolsEnabled = unchanged
            env.handler.finishToolListChangeSessions()
            try #require(await MCPSubscriptionFixture.wait { stream.writer.finished.withLockedValue { $0 } })
            let messages = try stream.messages(); #expect(messages.count == 2)
            try assertComplete(messages[1], id: 7)
        } catch { await stream.close(); throw error }
        await stream.close(); #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test(arguments: [false, true]) func disconnectAndTaskCancellationUnregisterExactlyOnce(cancel: Bool) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let original = env.mcpSettings.maintenanceToolsEnabled
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler)
        do {
            try requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            if cancel {
                stream.cancelBodyOnly()
                try #require(await MCPSubscriptionFixture.wait { stream.writer.bodyCompleted.withLockedValue { $0 } })
                try #require(await MCPSubscriptionFixture.wait { env.handler.activeToolListChangeStreamCount == 0 })
            }
            await stream.close(cancelBody: false)
            #expect(stream.writer.bodyCompleted.withLockedValue { $0 })
            try #require(await MCPSubscriptionFixture.wait { env.handler.activeToolListChangeStreamCount == 0 })
            let bytes = stream.writer.bytes.withLockedValue { $0 }
            env.mcpSettings.maintenanceToolsEnabled.toggle()
            env.handler.finishToolListChangeSessions()
            #expect(stream.writer.bytes.withLockedValue { $0 } == bytes)
            await stream.close(cancelBody: cancel)
        } catch { await stream.close(); env.mcpSettings.maintenanceToolsEnabled = original; throw error }
        env.mcpSettings.maintenanceToolsEnabled = original
    }

    @Test func writerFailureUnregistersWithoutWaitingForChannelDisconnect() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler)
        do {
            try requireStream(stream); stream.writer.failWrites.withLockedValue { $0 = true }; stream.startBody()
            try #require(await MCPSubscriptionFixture.wait { env.handler.activeToolListChangeStreamCount == 0 })
            let bytes = stream.writer.bytes.withLockedValue { $0 }
            env.handler.finishToolListChangeSessions()
            #expect(stream.writer.bytes.withLockedValue { $0 } == bytes)
        } catch { await stream.close(); throw error }
        await stream.close()
    }

    @Test func stopWithoutListenerClosesRegisteredRequestWithCompleteResult() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler, id: "no-listener")
        do {
            try requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            await server.stop()
            try #require(await MCPSubscriptionFixture.wait { stream.writer.finished.withLockedValue { $0 } })
            let messages = try stream.messages(); #expect(messages.count == 2)
            try assertComplete(messages[1], id: "no-listener")
            #expect(env.handler.activeToolListChangeStreamCount == 0)
        } catch { await stream.close(); await server.stop(); throw error }
        await stream.close(); await server.stop()
    }

    @Test func openSubscriptionNeverConsumesCoveredReadAdmission() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let source = NoCapture()
        let service = MCPReadService(source: source,
            monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil),
            snapshots: env.handler.taskQuerySnapshots)
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings,
            taskQuerySnapshots: env.handler.taskQuerySnapshots, writeCoordinator: env.writeCoordinator,
            readService: service, readCoordinator: env.handler.readCoordinator)
        let stream = try await MCPSubscriptionFixture.open(handler: handler)
        do {
            try requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            #expect(env.handler.readCoordinator.unfinishedCount == 0 && source.calls == 0)
            #expect(env.handler.activeToolListChangeStreamCount == 1)
            env.handler.finishToolListChangeSessions()
            try #require(await MCPSubscriptionFixture.wait { stream.writer.finished.withLockedValue { $0 } })
            #expect(env.handler.readCoordinator.unfinishedCount == 0 && source.calls == 0)
        } catch { await stream.close(); throw error }
        await stream.close()
    }

    @MainActor private final class NoCapture: MCPReadCaptureSource {
        var calls = 0
        func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
            calls += 1
            throw MCPReadCaptureError.storageFailure
        }
    }

    static func requireStream(_ stream: MCPSubscriptionFixture) throws {
        try #require(stream.response.status == .ok)
        #expect(stream.response.headers[.contentType] == "text/event-stream")
        #expect(stream.response.headers[.cacheControl] == "no-cache")
        #expect(stream.response.headers[.mcpSessionID] == nil)
    }
    private func requireStream(_ stream: MCPSubscriptionFixture) throws { try Self.requireStream(stream) }
    private func assertAck(_ message: [String: Any], id: Any, accepted: [String: Bool]) throws {
        #expect(message["jsonrpc"] as? String == "2.0")
        #expect(message["method"] as? String == "notifications/subscriptions/acknowledged")
        let params = try #require(message["params"] as? [String: Any])
        #expect(params["notifications"] as? [String: Bool] == accepted)
        #expect(message["id"] == nil && message["result"] == nil)
        try MCPSubscriptionFixture.assertID(message, expected: id)
    }
    private func assertChange(_ message: [String: Any], id: Any) throws {
        #expect(message["jsonrpc"] as? String == "2.0")
        #expect(message["method"] as? String == "notifications/tools/list_changed")
        #expect(message["id"] == nil && message["result"] == nil)
        try MCPSubscriptionFixture.assertID(message, expected: id)
    }
    static func assertComplete(_ message: [String: Any], id: Any) throws {
        #expect(message["jsonrpc"] as? String == "2.0")
        #expect(message["method"] == nil)
        #expect(try JSONSerialization.data(withJSONObject: [try #require(message["id"])])
            == JSONSerialization.data(withJSONObject: [id]))
        let result = try #require(message["result"] as? [String: Any])
        #expect(result["resultType"] as? String == "complete")
        #expect(message["error"] == nil)
        let meta = try #require(result["_meta"] as? [String: Any])
        let subscriptionID = try #require(meta["io.modelcontextprotocol/subscriptionId"])
        #expect(try JSONSerialization.data(withJSONObject: [subscriptionID])
            == JSONSerialization.data(withJSONObject: [id]))
    }
    private func assertComplete(_ message: [String: Any], id: Any) throws { try Self.assertComplete(message, id: id) }
}
#endif
