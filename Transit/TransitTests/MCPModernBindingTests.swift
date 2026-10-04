#if os(macOS)
import Foundation
import HTTPTypes
import HummingbirdCore
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPModernBindingTests {
    @Test func unsupportedNestedArgumentsNeverCollapseOrBecomeAbsent() throws {
        for arguments in [
            #"{"metadata":{"é":"first","e\u0301":"second"}}"#,
            #"{"metadata":[{"é":"first","e\u0301":"second"}]}"#,
            #"{"limit":1E+9999}"#
        ] {
            let modern = try request(tool: "query_tasks", arguments: arguments)
            let rpc = MCPModernWire.request(modern, tool: "query_tasks")
            let read = try #require(MCPBoundedReadDispatcher.classify(rpc))
            #expect(read.malformedArguments)
            let params = try #require(rpc.params?.value as? [String: Any])
            #expect(params["arguments"] != nil)
            #expect(params["arguments"] as? [String: Any] == nil)
        }
    }

    @Test func unsupportedProtectedArgumentsRejectBeforeAnyEffect() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let modern = try request(tool: "create_project", arguments:
            """
            {"name":"Must not exist","colorHex":"#334455","idempotencyKey":"collision",
            "metadata":{"é":1,"e\\u0301":2}}
            """)
        let rpc = MCPModernWire.request(modern, tool: "create_project")
        let selected = try await MCPModernProviderBinding.call(rpc, tool: "create_project",
            handler: env.handler, maintenanceEnabled: false)
        guard case .normal(let bytes) = selected else {
            Issue.record("Unsupported argument envelope must return a request error without dispatch")
            return
        }
        let document = try MCPJSONDocument.parse(bytes)
        let error = try #require(MCPResultEncoderFixtures.field("error", in: document.value))
        #expect(MCPResultEncoderFixtures.field("result", in: document.value) == nil)
        #expect(MCPResultEncoderFixtures.field("code", in: error) != nil)
        #expect(try env.context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func availabilitySnapshotReflectsStoredInitialAndImmediateAssignments() async throws {
        let key = "mcpMaintenanceToolsEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        let settings = MCPSettings()
        #expect(settings.maintenanceToolsEnabledSnapshot)
        #expect(await Task.detached { settings.maintenanceToolsEnabledSnapshot }.value)
        settings.maintenanceToolsEnabled = false
        #expect(!settings.maintenanceToolsEnabledSnapshot)
        #expect(!(await Task.detached { settings.maintenanceToolsEnabledSnapshot }.value))
        let off = MCPModernProviderBinding.availability(maintenanceEnabled: settings.maintenanceToolsEnabledSnapshot)
        #expect(!off.tools.contains { $0.name == "reassign_duplicate_display_ids" })
        settings.maintenanceToolsEnabled = true
        #expect(settings.maintenanceToolsEnabledSnapshot)
        #expect(MCPModernProviderBinding.availability(maintenanceEnabled: true).tools.contains {
            $0.name == "reassign_duplicate_display_ids"
        })
    }

    @Test func snapshotAssignmentsKeepExistingChangeNotificationSemantics() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let settings = env.mcpSettings
        settings.maintenanceToolsEnabled = false
        let loop = NIOAsyncTestingEventLoop()
        let closed = loop.makePromise(of: Void.self)
        do {
            let subscription = try settings.subscriptionBroadcaster.subscribe(id: .string("availability"),
                toolsListChanged: true, channelClose: closed.futureResult)
            settings.maintenanceToolsEnabled = false
            settings.maintenanceToolsEnabled = true
            #expect(settings.maintenanceToolsEnabledSnapshot)
            settings.finishToolListChangeSessions()
            let ack = try #require(try JSONSerialization.jsonObject(
                with: subscription.acknowledgement) as? [String: Any])
            #expect(ack["method"] as? String == "notifications/subscriptions/acknowledged")
            var methods: [String] = []
            for await frame in subscription.changes {
                let notification = try #require(try JSONSerialization.jsonObject(with: frame) as? [String: Any])
                methods.append(try #require(notification["method"] as? String))
            }
            #expect(methods == ["notifications/tools/list_changed"])
            #expect(subscription.delivery.completesGracefully)
            let complete = try #require(try JSONSerialization.jsonObject(
                with: subscription.completion) as? [String: Any])
            let result = try #require(complete["result"] as? [String: Any])
            #expect(result["resultType"] as? String == "complete")
            #expect(complete["id"] as? String == "availability")
            closed.succeed(())
            await loop.shutdownGracefully()
        } catch {
            settings.finishToolListChangeSessions()
            closed.succeed(())
            await loop.shutdownGracefully()
            throw error
        }
    }

    @Test func cancellationDuringBlockedAcknowledgementUnregistersBeforeWriterReturns() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler)
        do {
            try #require(stream.response.status == .ok)
            stream.writer.blockNextWrite()
            stream.startBody()
            try #require(await MCPSubscriptionFixture.wait {
                stream.writer.blockedWriteEntered.withLockedValue { $0 }
            })
            stream.cancelBodyOnly()
            try #require(await MCPSubscriptionFixture.wait { env.handler.activeToolListChangeStreamCount == 0 })
            #expect(!stream.writer.bodyCompleted.withLockedValue { $0 })
            stream.writer.releaseBlockedWrite()
            try #require(await MCPSubscriptionFixture.wait { stream.writer.bodyCompleted.withLockedValue { $0 } })
            #expect(try stream.messages().count == 1)
            await stream.close()
        } catch {
            stream.writer.releaseBlockedWrite()
            await stream.close()
            throw error
        }
    }

    @Test func shutdownFenceRejectsLateRegistrationAndReopenOwnsReplacement() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let old = try await MCPSubscriptionFixture.open(handler: env.handler, id: "old")
        var replacement: MCPSubscriptionFixture?
        var lateRequest: MCPSubscriptionFixture?
        do {
            try #require(old.response.status == .ok)
            env.handler.finishToolListChangeSessions()
            let late = try await MCPSubscriptionFixture.open(handler: env.handler, id: "late")
            lateRequest = late
            #expect(late.response.status == .serviceUnavailable)
            late.startBody()
            try #require(await MCPSubscriptionFixture.wait { late.writer.bodyCompleted.withLockedValue { $0 } })
            let rejected = try #require(try JSONSerialization.jsonObject(
                with: Data(late.writer.bytes.withLockedValue { $0.readableBytesView })) as? [String: Any])
            #expect(rejected["id"] as? String == "late")
            #expect((rejected["error"] as? [String: Any])?["code"] as? Int == -32603)
            #expect(env.handler.activeToolListChangeStreamCount == 0)
            await late.close()
            env.handler.openToolListSubscriptions()
            let next = try await MCPSubscriptionFixture.open(handler: env.handler, id: "new")
            replacement = next
            try #require(next.response.status == .ok)
            #expect(env.handler.activeToolListChangeStreamCount == 1)
            old.startBody()
            try #require(await MCPSubscriptionFixture.wait { old.writer.bodyCompleted.withLockedValue { $0 } })
            let messages = try old.messages()
            try #require(messages.count == 2)
            try MCPToolListChangeNotificationTests.assertComplete(messages[1], id: "old")
            #expect(env.handler.activeToolListChangeStreamCount == 1)
            await old.close()
            await next.close()
        } catch {
            await lateRequest?.close()
            await replacement?.close()
            await old.close()
            throw error
        }
    }

    @Test func unsupportedHTTPMethodsReturn405AndNeverDispatch() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let methods: [HTTPRequest.Method] = [.get, .delete, .head, .put, .patch, .options, .trace, .connect]
        for method in methods {
            let response = try await MCPModernResultFixture.transport(handler: env.handler, method: method,
                body: "{not parsed", loggerLabel: "t2383-modern-method-rejection")
            #expect(response.status == .methodNotAllowed)
            #expect(response.headers[.allow] == "POST")
            let forbidden = try await MCPModernResultFixture.transport(handler: env.handler, method: method,
                origin: "https://untrusted.example", body: "{not parsed", loggerLabel: "t2383-modern-origin-first")
            #expect(forbidden.status == .forbidden)
        }
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    private func request(tool: String, arguments: String) throws -> MCPModernRequest {
        let text = """
        {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\(tool)","arguments":\(arguments),
        "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",
        "io.modelcontextprotocol/clientCapabilities":{}}}}
        """
        let input = MCPModernRequestInput(httpMethod: "POST", headers: [
            .init(name: "Host", value: "127.0.0.1:3141"),
            .init(name: "Content-Type", value: "application/json"),
            .init(name: "Accept", value: "application/json, text/event-stream"),
            .init(name: "MCP-Protocol-Version", value: "2026-07-28"),
            .init(name: "Mcp-Method", value: "tools/call"), .init(name: "Mcp-Name", value: tool)
        ], body: Data(text.utf8))
        return try MCPModernValidator.validate(input,
            availability: MCPModernProviderBinding.availability(maintenanceEnabled: false))
    }
}
#endif
