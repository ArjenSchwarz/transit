#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1555: The MCP update_milestone handler must expose the same description
// clear semantics as update_task — an empty or whitespace-only string clears
// the stored description back to nil (and the response omits the key), instead
// of persisting an empty string. Non-empty values are trimmed and stored.
@MainActor @Suite(.serialized)
struct MCPMilestoneClearDescriptionTests {

    @Test func updateMilestoneTrimsNonEmptyDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: "old", project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["milestoneId": milestone.id.uuidString, "description": "  text  "]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] as? String == "text")
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == "text")
    }

    @Test func updateMilestoneEmptyDescriptionClears() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: "current", project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["milestoneId": milestone.id.uuidString, "description": ""]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] == nil, "Response should omit description when cleared")
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == nil)
    }

    @Test func updateMilestoneWhitespaceDescriptionClears() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: "current", project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["milestoneId": milestone.id.uuidString, "description": "   "]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] == nil, "Response should omit description when cleared")
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == nil)
    }

    // Clearing the description alongside a status change applies both atomically.
    @Test func updateMilestoneClearsDescriptionAndChangesStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: "current", project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "description": "",
                "status": "done"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] == nil, "Response should omit description when cleared")
        #expect(result["status"] as? String == "done")
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == nil)
        #expect(refreshed.statusRawValue == "done")
    }
}

#endif
