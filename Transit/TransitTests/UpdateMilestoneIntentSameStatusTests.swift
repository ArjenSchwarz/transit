import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-923: `UpdateMilestoneIntent` must treat same-status updates
/// as no-ops for status side effects. Otherwise an old `done`/`abandoned` milestone
/// re-enters the current report window through `ReportLogic`'s
/// `completionDate ?? lastStatusChangeDate` fallback.
@MainActor @Suite(.serialized)
struct UpdateMilestoneIntentSameStatusTests {

    private struct Services {
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeMilestone(
        in context: ModelContext,
        name: String,
        project: Project,
        displayId: Int,
        status: MilestoneStatus = .open
    ) -> Milestone {
        let milestone = Milestone(name: name, description: nil, project: project, displayID: .permanent(displayId))
        if status != .open {
            milestone.statusRawValue = status.rawValue
            milestone.lastStatusChangeDate = Date.now
            if status.isTerminal {
                milestone.completionDate = Date.now
            }
        }
        context.insert(milestone)
        return milestone
    }

    @Test func sameTerminalStatusPreservesCompletionDate() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .done)
        let originalCompletionDate = try #require(milestone.completionDate)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate

        let input = """
        {"displayId":1,"status":"done"}
        """

        _ = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let refetched = try svc.milestone.findByDisplayID(1)
        #expect(refetched.completionDate == originalCompletionDate)
        #expect(refetched.lastStatusChangeDate == originalLastStatusChangeDate)
    }

    @Test func sameStatusWithOtherFieldPreservesTimestamps() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .done)
        let originalCompletionDate = try #require(milestone.completionDate)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate

        let input = """
        {"displayId":1,"status":"done","description":"Now with notes"}
        """

        _ = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let refetched = try svc.milestone.findByDisplayID(1)
        #expect(refetched.milestoneDescription == "Now with notes")
        #expect(refetched.completionDate == originalCompletionDate)
        #expect(refetched.lastStatusChangeDate == originalLastStatusChangeDate)
    }

    /// Re-submitting the same non-terminal status must not rewrite `lastStatusChangeDate`.
    @Test func sameOpenStatusPreservesLastStatusChangeDate() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .open)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate

        let input = """
        {"displayId":1,"status":"open"}
        """

        _ = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let refetched = try svc.milestone.findByDisplayID(1)
        #expect(refetched.lastStatusChangeDate == originalLastStatusChangeDate)
        #expect(refetched.completionDate == nil)
    }
}
