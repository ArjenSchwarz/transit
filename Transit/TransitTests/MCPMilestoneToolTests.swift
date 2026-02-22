#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPMilestoneToolTests {

    // MARK: - tools/list includes milestone tools

    @Test func toolsListIncludesMilestoneTools() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try #require(await env.handler.handle(MCPTestHelpers.request(method: "tools/list")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])

        let names = tools.compactMap { $0["name"] as? String }
        #expect(names.contains("create_milestone"))
        #expect(names.contains("query_milestones"))
        #expect(names.contains("update_milestone"))
        #expect(names.contains("delete_milestone"))
        #expect(names.contains("update_task"))
        #expect(tools.count == 10)
    }

    // MARK: - create_milestone

    @Test func createMilestoneSuccess() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0",
                "projectId": project.id.uuidString,
                "description": "First release"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "v1.0")
        #expect(result["status"] as? String == "open")
        #expect(result["displayId"] as? Int == 1)
        #expect(result["description"] as? String == "First release")
        #expect(result["milestoneId"] is String)
    }

    @Test func createMilestoneByProjectName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0", "project": "Alpha"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "v1.0")
        #expect(result["projectName"] as? String == "Alpha")
    }

    @Test func createMilestoneMissingNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["project": "Test"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func createMilestoneMissingProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func createMilestoneDuplicateNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["name": "v1.0", "projectId": project.id.uuidString]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - query_milestones

    @Test func queryAllMilestones() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        _ = try await env.milestoneService.createMilestone(name: "v2.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func queryMilestonesByProject() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: projectA)
        _ = try await env.milestoneService.createMilestone(name: "v2.0", description: nil, project: projectB)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["project": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "v1.0")
    }

    @Test func queryMilestonesByStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        _ = try await env.milestoneService.createMilestone(name: "v2.0", description: nil, project: project)
        try env.milestoneService.updateStatus(milestone, to: .done)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["status": ["open"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "v2.0")
    }

    @Test func queryMilestonesBySearch() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: "First release", project: project)
        _ = try await env.milestoneService.createMilestone(name: "Beta", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": "release"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "v1.0")
    }

    @Test func queryMilestoneByDisplayIdReturnsDetail() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["displayId": 1]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        let first = try #require(results.first)
        #expect(first["name"] as? String == "v1.0")
        let tasks = try #require(first["tasks"] as? [[String: Any]])
        #expect(tasks.count == 1)
        #expect(tasks.first?["name"] as? String == "Task A")
    }

    @Test func queryMilestoneByDisplayIdNotFoundReturnsEmpty() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["displayId": 999]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    // MARK: - update_milestone

    @Test func updateMilestoneStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": 1, "status": "done"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "done")
        #expect(result["previousStatus"] as? String == "open")
    }

    @Test func updateMilestoneName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": 1, "name": "v1.1"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "v1.1")
    }

    @Test func updateMilestoneNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": 999, "name": "v2.0"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func updateMilestoneInvalidStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": 1, "status": "invalid"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - delete_milestone

    @Test func deleteMilestoneSuccess() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["displayId": 1]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["deleted"] as? Bool == true)
        #expect(result["name"] as? String == "v1.0")
        #expect(result["affectedTasks"] as? Int == 1)
    }

    @Test func deleteMilestoneNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["displayId": 999]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

}

#endif
