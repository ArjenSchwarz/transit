#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPToolHandlerDisplayIdTests {

    @Test func queryByDisplayIdReturnsDetailedTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Lookup Me",
            description: "A detailed description",
            type: .bug,
            project: project,
            metadata: ["git.branch": "feature/test"]
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        let task = try #require(results.first)
        #expect(task["name"] as? String == "Lookup Me")
        #expect(task["description"] as? String == "A detailed description")
        let metadata = try #require(task["metadata"] as? [String: String])
        #expect(metadata["git.branch"] == "feature/test")
    }

    @Test func queryByDisplayIdNotFoundReturnsEmptyArray() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 999]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func queryByDisplayIdWithNonMatchingStatusReturnsEmpty() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1, "status": "planning"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func queryByDisplayIdWithMatchingFilterReturnsTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Bug Task", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1, "type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Bug Task")
    }

    @Test func queryByDisplayIdOmitsDescriptionWhenNil() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "No Desc", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let task = try #require(results.first)
        // description key should be present but null (serialized as NSNull)
        #expect(task["name"] as? String == "No Desc")
        #expect(task.keys.contains("description"))
        #expect(task["description"] is NSNull)
    }

    @Test(arguments: [-1, 0])
    func queryByInvalidDisplayIdReturnsEmpty(displayId: Int) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Real Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": displayId]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func queryWithoutDisplayIdOmitsDescriptionAndMetadata() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Regular", description: "Has desc", type: .feature, project: project,
            metadata: ["key": "value"]
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let task = try #require(results.first)
        #expect(task["description"] == nil)
        #expect(task["metadata"] == nil)
    }
}

#endif
