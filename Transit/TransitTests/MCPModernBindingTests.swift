#if os(macOS)
import Foundation
import HTTPTypes
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
            let session = settings.createToolListChangeSession()
            let notifications = try #require(settings.toolListChangeNotifications(sessionID: session,
                channelClose: closed.futureResult))
            settings.maintenanceToolsEnabled = false
            settings.maintenanceToolsEnabled = true
            #expect(settings.maintenanceToolsEnabledSnapshot)
            settings.finishToolListChangeSessions()
            var methods: [String] = []
            for await notification in notifications { methods.append(notification.method) }
            #expect(methods == ["notifications/tools/list_changed"])
            closed.succeed(())
            await loop.shutdownGracefully()
        } catch {
            settings.finishToolListChangeSessions()
            closed.succeed(())
            await loop.shutdownGracefully()
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
