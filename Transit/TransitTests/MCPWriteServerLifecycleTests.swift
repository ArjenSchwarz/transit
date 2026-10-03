#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

extension MCPServerLifecycleTests {
    @Test func listenerRestartKeepsAcceptedWriteAndScopeLock() async throws {
        let counter = MCPWriteLifecycleCounter()
        let env = try MCPTestHelpers.makeEnv(taskCounterStore: counter)
        let project = MCPTestHelpers.makeProject(in: env.context)
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()
        await server.start(port: port)
        try #require(await waitUntilListening(port: port))
        let args: [String: Any] = ["name": "restart", "type": "feature",
                                  "projectId": project.id.uuidString, "idempotencyKey": "restart-write"]
        let operation = Task {
            await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "create_task", arguments: args))
        }
        await counter.waitForLoad()
        await server.restart(port: port)
        #expect(await waitUntilListening(port: port))
        let competing = MCPWriteCoordinator(
            services: MCPWriteCommandServices(tasks: env.taskService, projects: env.projectService,
                comments: env.commentService, milestones: env.milestoneService, context: env.context),
            sidecarDirectory: env.sidecarDirectory
        )
        let busy = await competing.execute(tool: "create_project", arguments: [
            "name": "blocked", "colorHex": "#123456", "idempotencyKey": "competing"
        ])
        #expect(busy.content.first?.text.contains("STORE_BUSY") == true)
        await counter.release()
        let response = await operation.value
        #expect(try MCPTestHelpers.decodeResult(response)["outcome"] as? String == "committed")
        let replay = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "create_task", arguments: args))
        #expect(try MCPTestHelpers.decodeResult(replay)["outcome"] as? String == "committed")
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).count == 1)
        await server.stop()
    }
}
#endif
