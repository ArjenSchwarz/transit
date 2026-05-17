import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1062 regression: the `DataMaintenanceView` result list combines task
/// and milestone duplicate groups into one `ForEach`. When the identity key
/// is just `displayId`, T-5 and M-5 collide in SwiftUI's diff and one row
/// is dropped. These tests pin the composite `stableID` shape and verify
/// the end-to-end reassignment flow returns unique stableIDs even when a
/// task pair and a milestone pair share the same `permanentDisplayId`.
@MainActor
@Suite(.serialized)
struct DataMaintenanceResultCollisionTests {

    private struct TestEnv {
        let context: ModelContext
        let service: DisplayIDMaintenanceService
        let project: Project
    }

    private func makeEnv() throws -> TestEnv {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 1))
        let milestoneAllocator = DisplayIDAllocator(
            store: InMemoryCounterStore(initialNextDisplayID: 1)
        )
        let commentService = CommentService(modelContext: context)
        let service = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: taskAllocator,
            milestoneAllocator: milestoneAllocator,
            commentService: commentService,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let project = Project(name: "Test", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return TestEnv(context: context, service: service, project: project)
    }

    /// Reassignment over a database that contains BOTH a duplicate task pair
    /// and a duplicate milestone pair at the same displayId (5) must produce
    /// two groups with distinct `stableID` values. A non-unique set would
    /// collapse rows in the result view.
    @Test func reassignmentReturnsDistinctStableIDsForTaskAndMilestoneCollision() async throws {
        let env = try makeEnv()

        let taskWinner = TransitTask(
            name: "T Winner", type: .feature, project: env.project,
            displayID: .permanent(5)
        )
        taskWinner.creationDate = Date(timeIntervalSince1970: 1000)
        env.context.insert(taskWinner)

        let taskLoser = TransitTask(
            name: "T Loser", type: .feature, project: env.project,
            displayID: .permanent(5)
        )
        taskLoser.creationDate = Date(timeIntervalSince1970: 2000)
        env.context.insert(taskLoser)

        let milestoneWinner = Milestone(
            name: "M Winner", project: env.project, displayID: .permanent(5)
        )
        milestoneWinner.creationDate = Date(timeIntervalSince1970: 1500)
        env.context.insert(milestoneWinner)

        let milestoneLoser = Milestone(
            name: "M Loser", project: env.project, displayID: .permanent(5)
        )
        milestoneLoser.creationDate = Date(timeIntervalSince1970: 2500)
        env.context.insert(milestoneLoser)

        try env.context.save()

        let result = await env.service.reassignDuplicates()

        #expect(result.status == .ok)
        #expect(result.groups.count == 2)

        let types = Set(result.groups.map(\.type))
        #expect(types == Set([.task, .milestone]))

        let stableIDs = result.groups.map(\.stableID)
        #expect(
            Set(stableIDs).count == stableIDs.count,
            "Task and milestone groups at the same displayId must have distinct stableIDs"
        )
        #expect(Set(stableIDs) == Set(["task-5", "milestone-5"]))
    }
}
