#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-830: Reject non-string milestone status on query_milestones / update_milestone.
// Split out of MCPToolHandlerEnumValidationTests.swift to stay under the
// type_body_length and file_length limits.
@MainActor @Suite(.serialized)
struct MCPMilestoneStatusValidationTests {

    @Test func queryMilestonesBooleanStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "M1", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["status": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status"))
    }

    // update_milestone: numeric status must be rejected before applying any other update.
    @Test func updateMilestoneNumericStatusReturnsErrorAndDoesNotRename() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "status": 123,
                "name": "Renamed"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status"))

        // Name must not have been changed
        let refreshed = try env.milestoneService.findByID(milestone.id)
        #expect(refreshed.name == "v1.0")
        #expect(refreshed.statusRawValue == "open")
    }

    @Test func updateMilestoneBooleanStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: [
                "milestoneId": milestone.id.uuidString,
                "status": false
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status"))
    }
}

#endif
