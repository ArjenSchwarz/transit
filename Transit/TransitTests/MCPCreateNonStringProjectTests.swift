#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1453: The MCP creation paths read `project` with `as? String` after only
// validating `projectId`. A present-but-non-string `project` (number, boolean,
// array, object) was silently treated as absent, so the request fell through to
// the generic missing-project error instead of rejecting the malformed field with
// `project must be a string`. Mirrors the T-1116 pattern already enforced by the
// query handlers. projectId-takes-precedence is preserved: a valid projectId wins
// and the malformed `project` value is ignored.
@MainActor @Suite(.serialized)
struct MCPCreateNonStringProjectTests {

    // MARK: - create_task

    @Test func createTaskNumericProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "X", "type": "bug", "project": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createTaskBooleanProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "X", "type": "bug", "project": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createTaskArrayProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "X", "type": "bug", "project": ["Alpha"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createTaskObjectProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "X", "type": "bug", "project": [String: Any]()]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createTaskValidProjectIdIgnoresNonStringProjectName() async throws {
        // projectId-takes-precedence: a valid projectId must win even when the
        // `project` name is malformed. Guards against an over-strict fix.
        let env = try MCPTestHelpers.makeEnv()
        let target = MCPTestHelpers.makeProject(in: env.context, name: "Target")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "X", "type": "bug",
                "projectId": target.id.uuidString, "project": 123
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let taskIdStr = try #require(result["taskId"] as? String)
        let taskId = try #require(UUID(uuidString: taskIdStr))
        let task = try env.taskService.findByID(taskId)
        #expect(task.project?.id == target.id)
    }

    // MARK: - create_milestone

    @Test func createMilestoneNumericProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0", "project": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createMilestoneBooleanProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0", "project": false]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createMilestoneArrayProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0", "project": ["Alpha"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createMilestoneObjectProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        _ = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0", "project": [String: Any]()]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func createMilestoneValidProjectIdIgnoresNonStringProjectName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let target = MCPTestHelpers.makeProject(in: env.context, name: "Target")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0",
                "projectId": target.id.uuidString, "project": 123
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let projectId = try #require(result["projectId"] as? String)
        #expect(projectId == target.id.uuidString)
    }
}

#endif
