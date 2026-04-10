#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-723: MCP create_task must drop non-string metadata values
/// instead of coercing them via string interpolation.
@MainActor @Suite(.serialized)
struct MCPCreateTaskMetadataTests {

    @Test func createTaskDropsNonStringMetadataValues() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Meta Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "metadata": ["priority": 1, "labels": ["a", "b"], "owner": "sam"] as [String: Any]
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let taskIdStr = try #require(result["taskId"] as? String)
        let taskId = try #require(UUID(uuidString: taskIdStr))
        let task = try env.taskService.findByID(taskId)
        // Non-string values must be dropped, only "owner" survives
        #expect(task.metadata == ["owner": "sam"])
    }

    @Test func createTaskPreservesAllStringMetadata() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Meta Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "metadata": ["git.branch": "main", "agent.id": "copilot"] as [String: String]
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let taskIdStr = try #require(result["taskId"] as? String)
        let taskId = try #require(UUID(uuidString: taskIdStr))
        let task = try env.taskService.findByID(taskId)
        #expect(task.metadata == ["git.branch": "main", "agent.id": "copilot"])
    }

    @Test func createTaskMetadataAllNonStringYieldsNoMetadata() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Meta Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "metadata": ["priority": 1, "retries": 2] as [String: Any]
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let taskIdStr = try #require(result["taskId"] as? String)
        let taskId = try #require(UUID(uuidString: taskIdStr))
        let task = try env.taskService.findByID(taskId)
        // All values are non-string, so metadata should be empty
        #expect(task.metadata.isEmpty)
    }
}

#endif
