#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPMilestoneDeleteTests {

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
