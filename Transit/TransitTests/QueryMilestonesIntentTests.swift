import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct QueryMilestonesIntentTests {

    // MARK: - Helpers

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

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Success Cases

    @Test func emptyInputReturnsAllMilestones() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "", milestoneService: svc.milestone, projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
    }

    @Test func filterByDisplayIdReturnsSingleMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1}", milestoneService: svc.milestone,
            projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "v1.0")
        // Single lookup includes tasks array
        #expect(parsed.first?["tasks"] is [[String: Any]])
    }

    @Test func filterByProjectReturnsMatchingMilestones() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)
        makeMilestone(in: svc.context, name: "v1.0", project: beta, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"project\":\"Alpha\"}", milestoneService: svc.milestone,
            projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["projectName"] as? String == "Alpha")
    }

    @Test func filterByStatusReturnsMatchingMilestones() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .done)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2, status: .open)

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":\"open\"}", milestoneService: svc.milestone,
            projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "v2.0")
    }

    @Test func filterBySearchMatchesNameAndDescription() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let alphaRelease = Milestone(
            name: "Alpha Release", description: "First release",
            project: project, displayID: .permanent(1)
        )
        svc.context.insert(alphaRelease)
        let betaMilestone = Milestone(
            name: "Beta", description: "Second alpha attempt",
            project: project, displayID: .permanent(2)
        )
        svc.context.insert(betaMilestone)
        makeMilestone(in: svc.context, name: "Gamma", project: project, displayId: 3)

        let result = QueryMilestonesIntent.execute(
            input: "{\"search\":\"alpha\"}", milestoneService: svc.milestone,
            projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
    }

    @Test func unknownDisplayIdReturnsEmptyArray() throws {
        let svc = try makeServices()

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":999}", milestoneService: svc.milestone,
            projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // MARK: - Error Cases

    @Test func malformedJSONReturnsInvalidInput() throws {
        let svc = try makeServices()

        let result = QueryMilestonesIntent.execute(
            input: "not json", milestoneService: svc.milestone,
            projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }
}
