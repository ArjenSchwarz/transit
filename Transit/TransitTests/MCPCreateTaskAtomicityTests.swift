#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPCreateTaskAtomicityTests {

    @Test func createTaskWithMilestoneSaveFailureIsAtomic() async throws {
        var expectedMilestoneID: UUID?
        let env = try MCPTestHelpers.makeEnv { context in
            let pendingTasks = try context.fetch(FetchDescriptor<TransitTask>())
            #expect(pendingTasks.count == 1)
            #expect(pendingTasks.first?.milestone?.id == expectedMilestoneID)
            throw SaveFailure.simulated
        }
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        expectedMilestoneID = milestone.id

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Atomic Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": milestone.permanentDisplayId!
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        try env.context.save()
        #expect(
            try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty,
            "A later save must not resurrect a failed aggregate create [T-1768]"
        )
    }
}
#endif
