#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import Testing
@testable import Transit

/// Synthetic store/listeners on ephemeral loopback ports; never the production/default listener.
@MainActor @Suite(.serialized)
struct MCPSubscriptionLifecycleTests {
    @Test(arguments: ["stop", "restart", "port-change"])
    func lifecycleClosesOldRequestWithCorrelatedCompleteBeforeEnding(action: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let helpers = MCPServerLifecycleTests()
        var firstPort = try helpers.availableLoopbackPort()
        while firstPort == MCPSettings.defaultPort { firstPort = try helpers.availableLoopbackPort() }
        var nextPort = try helpers.availableLoopbackPort()
        while nextPort == firstPort || nextPort == MCPSettings.defaultPort {
            nextPort = try helpers.availableLoopbackPort()
        }
        try #require(firstPort != MCPSettings.defaultPort)
        var ownedStream: MCPSubscriptionFixture?
        do {
            await server.start(port: firstPort)
            try #require(await helpers.waitUntilListening(port: firstPort))
            let stream = try await MCPSubscriptionFixture.open(handler: env.handler, id: action)
            ownedStream = stream
            try MCPToolListChangeNotificationTests.requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            let previousGeneration = server.listenerGeneration
            switch action {
            case "stop": await server.stop()
            case "restart": await server.restart(port: firstPort)
            default: await server.start(port: nextPort)
            }
            try #require(await MCPSubscriptionFixture.wait { stream.writer.finished.withLockedValue { $0 } })
            let messages = try stream.messages(); try #require(messages.count == 2)
            try MCPToolListChangeNotificationTests.assertComplete(messages[1], id: action)
            #expect(env.handler.activeToolListChangeStreamCount == 0)
            if action != "stop" {
                let replacement = try await MCPSubscriptionFixture.open(handler: env.handler, id: "replacement")
                do {
                    try MCPToolListChangeNotificationTests.requireStream(replacement); replacement.startBody()
                    try #require(try await MCPSubscriptionFixture.wait { try replacement.messages().count == 1 })
                    server.listenerDidExit(generation: previousGeneration, failure: "stale synthetic completion")
                    #expect(env.handler.activeToolListChangeStreamCount == 1)
                } catch { await replacement.close(); throw error }
                await replacement.close()
            }
        } catch { await ownedStream?.close(); await server.stop(); throw error }
        await ownedStream?.close(); await server.stop()
        #expect(!server.isRunning)
    }

    @Test func currentGenerationListenerFailureClearsRegistrationsEvenWithoutActiveListener() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let stream = try await MCPSubscriptionFixture.open(handler: env.handler, id: "listener-failure")
        do {
            try MCPToolListChangeNotificationTests.requireStream(stream); stream.startBody()
            try #require(try await MCPSubscriptionFixture.wait { try stream.messages().count == 1 })
            server.listenerDidExit(generation: server.listenerGeneration, failure: "synthetic listener failure")
            try #require(await MCPSubscriptionFixture.wait { env.handler.activeToolListChangeStreamCount == 0 })
            try #require(await MCPSubscriptionFixture.wait { stream.writer.finished.withLockedValue { $0 } })
            let messages = try stream.messages(); try #require(messages.count == 2)
            try MCPToolListChangeNotificationTests.assertComplete(messages[1], id: "listener-failure")
            #expect(server.startError == "synthetic listener failure")
        } catch { await stream.close(); await server.stop(); throw error }
        await stream.close(); await server.stop()
    }
}
#endif
