import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1555: UpdateMilestoneIntent must expose the same description clear semantics
// as update_task / the MCP update_milestone handler — an empty or whitespace-only
// string clears the stored description back to nil instead of persisting an empty
// string. Non-empty values are trimmed and stored.
@MainActor @Suite(.serialized)
struct UpdateMilestoneClearDescIntentTests {

    private struct Services {
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return Services(
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeMilestone(
        in context: ModelContext, project: Project, displayId: Int, description: String?
    ) -> Milestone {
        let milestone = Milestone(
            name: "v1.0", description: description, project: project, displayID: .permanent(displayId)
        )
        context.insert(milestone)
        return milestone
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func updateTrimsNonEmptyDescription() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, project: project, displayId: 1, description: "old")

        let result = UpdateMilestoneIntent.execute(
            input: #"{"displayId":1,"description":"  text  "}"#,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] as? String == "text")
        let refreshed = try svc.milestone.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == "text")
    }

    @Test func updateEmptyDescriptionClears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, project: project, displayId: 1, description: "current")

        let result = UpdateMilestoneIntent.execute(
            input: #"{"displayId":1,"description":""}"#,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] == nil, "Response should omit description when cleared")
        let refreshed = try svc.milestone.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == nil)
    }

    @Test func updateWhitespaceDescriptionClears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, project: project, displayId: 1, description: "current")

        let result = UpdateMilestoneIntent.execute(
            input: #"{"displayId":1,"description":"   "}"#,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] == nil, "Response should omit description when cleared")
        let refreshed = try svc.milestone.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == nil)
    }

    @Test func updateClearsDescriptionAndChangesStatus() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, project: project, displayId: 1, description: "current")

        let result = UpdateMilestoneIntent.execute(
            input: #"{"displayId":1,"description":"","status":"done"}"#,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "done")
        #expect(parsed["description"] == nil, "Response should omit description when cleared")
        let refreshed = try svc.milestone.findByID(milestone.id)
        #expect(refreshed.milestoneDescription == nil)
        #expect(refreshed.statusRawValue == "done")
    }
}
