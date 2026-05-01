#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-810: When milestoneId is present but not a String (number, boolean, etc.),
// the handler must reject it with the explicit "milestoneId must be a valid UUID"
// error rather than falling through to the generic "Provide either..." message.
@MainActor @Suite(.serialized)
struct MCPNonStringMilestoneIdTests {

    @Test func updateMilestoneWithNumericMilestoneIdReturnsSpecificError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["milestoneId": 42, "name": "v2.0"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneId must be a valid UUID"))
    }

    @Test func deleteMilestoneWithNumericMilestoneIdReturnsSpecificError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["milestoneId": 42]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneId must be a valid UUID"))
    }

    @Test func updateMilestoneWithBooleanMilestoneIdReturnsSpecificError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["milestoneId": true, "name": "v2.0"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneId must be a valid UUID"))
    }

    @Test func deleteMilestoneWithBooleanMilestoneIdReturnsSpecificError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "delete_milestone",
            arguments: ["milestoneId": false]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneId must be a valid UUID"))
    }
}

#endif
