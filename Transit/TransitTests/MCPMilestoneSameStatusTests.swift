#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-923: `update_milestone` must treat same-status updates
/// as no-ops for status side effects. Otherwise an old `done`/`abandoned` milestone
/// re-enters the current report window through `ReportLogic`'s
/// `completionDate ?? lastStatusChangeDate` fallback.
@MainActor @Suite(.serialized)
struct MCPMilestoneSameStatusTests {

    @Test func updateMilestoneSameTerminalStatusPreservesCompletionDate() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        try env.milestoneService.updateStatus(milestone, to: .done)
        let originalCompletionDate = try #require(milestone.completionDate)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate
        let displayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": displayId, "status": "done"]
        ))

        _ = try MCPTestHelpers.decodeResult(response)
        let refetched = try env.milestoneService.findByDisplayID(displayId)
        #expect(refetched.completionDate == originalCompletionDate)
        #expect(refetched.lastStatusChangeDate == originalLastStatusChangeDate)
    }

    @Test func updateMilestoneSameStatusWithOtherFieldPreservesTimestamps() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        try env.milestoneService.updateStatus(milestone, to: .done)
        let originalCompletionDate = try #require(milestone.completionDate)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate
        let displayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_milestone",
            arguments: ["displayId": displayId, "status": "done", "description": "Now with notes"]
        ))

        _ = try MCPTestHelpers.decodeResult(response)
        let refetched = try env.milestoneService.findByDisplayID(displayId)
        #expect(refetched.milestoneDescription == "Now with notes")
        #expect(refetched.completionDate == originalCompletionDate)
        #expect(refetched.lastStatusChangeDate == originalLastStatusChangeDate)
    }
}

#endif
