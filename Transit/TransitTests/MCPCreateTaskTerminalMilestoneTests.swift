#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-2037 regression: MCP task creation must reject terminal milestones before
/// inserting a task, while existing-task milestone assignment remains unchanged.
@MainActor @Suite(.serialized)
struct MCPCreateTaskTerminalMilestoneTests {

    @Test(arguments: [MilestoneStatus.done, .abandoned])
    func createTaskWithTerminalMilestoneReturnsErrorWithoutCreatingTask(
        terminalStatus: MilestoneStatus
    ) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        try env.milestoneService.updateStatus(milestone, to: terminalStatus)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Terminal Milestone Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": milestone.permanentDisplayId!
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("no longer open"))
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }
}
#endif
