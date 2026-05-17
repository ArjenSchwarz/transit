#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1230: Reject non-string `name` / `description` on MCP update_milestone.
// Mirrors the prior status validation work (T-830).
@MainActor @Suite(.serialized)
struct MCPMilestoneRenameValidationTests {

    // update_milestone: numeric name must be rejected before applying any other update.
    @Test func updateMilestoneNumericNameReturnsErrorAndDoesNotChangeStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "name": 123,
                "status": "done"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("name"))

        // Neither field must have been changed.
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.name == "v1.0")
        #expect(refreshed.statusRawValue == "open")
    }

    @Test func updateMilestoneBooleanNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "name": false
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("name"))
    }

    @Test func updateMilestoneNullNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "name": NSNull(),
                "status": "done"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("name"))

        // Status must not have been changed despite malformed name.
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.name == "v1.0")
        #expect(refreshed.statusRawValue == "open")
    }

    @Test func updateMilestoneArrayNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "name": ["v2.0"]
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("name"))
    }

    @Test func updateMilestoneNumericDescriptionReturnsError() async throws {
        // description is a string-only update field. A non-string value must be
        // rejected, not silently dropped while other fields apply.
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "description": 42,
                "status": "done"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("description"))

        // Status must not have been changed.
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.statusRawValue == "open")
    }
}

#endif
