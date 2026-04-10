#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPNonIntegerDisplayIdTests {

    // MARK: - query_tasks

    @Test(arguments: ["abc", "1.5", ""])
    func queryTasksWithNonIntegerDisplayIdReturnsError(displayId: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": displayId]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    @Test func queryTasksWithFloatDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1.5]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    @Test func queryTasksWithValidIntegerDisplayIdStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Task")
    }

    // MARK: - query_milestones

    @Test(arguments: ["abc", "1.5", ""])
    func queryMilestonesWithNonIntegerDisplayIdReturnsError(displayId: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "MS1", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["displayId": displayId]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    @Test func queryMilestonesWithFloatDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "MS1", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["displayId": 2.7]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    @Test func queryMilestonesWithValidIntegerDisplayIdStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "MS1", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["displayId": 1]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "MS1")
    }

    // MARK: - update_task_status

    @Test func updateStatusWithNonIntegerDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": "abc", "status": "planning"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - add_comment

    @Test func addCommentWithNonIntegerDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": "abc",
                "content": "A comment",
                "authorName": "Agent"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - update_task

    @Test func updateTaskWithNonIntegerDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": "abc"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - update_milestone

    @Test func updateMilestoneWithNonIntegerDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": "abc", "name": "Updated"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - delete_milestone

    @Test func deleteMilestoneWithNonIntegerDisplayIdReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["displayId": "abc"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
    }

    // MARK: - T-769: Malformed milestoneId must not silently fall through

    // T-769: When milestoneId is present but not a valid UUID, the error must explicitly
    // say the milestoneId is invalid, not give a generic "Provide either..." message.
    @Test(arguments: ["not-a-uuid", "abc", "123", ""])
    func updateMilestoneWithMalformedMilestoneIdReturnsSpecificError(milestoneId: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["milestoneId": milestoneId, "name": "v2.0"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneId must be a valid UUID"))
    }

    @Test(arguments: ["not-a-uuid", "abc", "123", ""])
    func deleteMilestoneWithMalformedMilestoneIdReturnsSpecificError(milestoneId: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["milestoneId": milestoneId]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneId must be a valid UUID"))
    }

    @Test func updateMilestoneWithMalformedDisplayIdDoesNotFallBackToMilestoneId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        // Both displayId (malformed) and milestoneId (valid) are present.
        // The handler must reject due to malformed displayId, not fall back to milestoneId.
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "displayId": "abc",
                "milestoneId": milestone.id.uuidString,
                "name": "v2.0"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
        // Verify the milestone was NOT updated
        let refetched = try env.milestoneService.findByDisplayID(1)
        #expect(refetched.name == "v1.0")
    }

    @Test func deleteMilestoneWithMalformedDisplayIdDoesNotFallBackToMilestoneId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        // Both displayId (malformed) and milestoneId (valid) are present.
        // The handler must reject due to malformed displayId, not fall back to milestoneId.
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: [
                "displayId": "abc",
                "milestoneId": milestone.id.uuidString
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))
        // Verify the milestone was NOT deleted
        let refetched = try env.milestoneService.findByDisplayID(1)
        #expect(refetched.name == "v1.0")
    }
}

#endif
