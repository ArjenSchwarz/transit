import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1266: QueryMilestonesIntent (Shortcuts JSON path) must reject a present-but-non-string
// `search` filter rather than silently dropping it via `as? String`. A dropped filter would
// return every milestone instead of an INVALID_INPUT error.
@MainActor @Suite(.serialized)
struct QueryMilestonesIntentSearchTests {

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
    private func makeMilestone(in context: ModelContext, name: String, project: Project, displayId: Int) -> Milestone {
        let milestone = Milestone(name: name, description: nil, project: project, displayID: .permanent(displayId))
        context.insert(milestone)
        return milestone
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test func numericSearchReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"search\":42}", milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let hint = parsed["hint"] as? String ?? ""
        #expect(hint.contains("search") && hint.contains("string"))
    }

    @Test func booleanSearchReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"search\":true}", milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let hint = parsed["hint"] as? String ?? ""
        #expect(hint.contains("search") && hint.contains("string"))
    }

    @Test func arraySearchReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"search\":[\"v1\"]}", milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let hint = parsed["hint"] as? String ?? ""
        #expect(hint.contains("search") && hint.contains("string"))
    }

    @Test func validStringSearchStillFilters() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "Alpha", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "Beta", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"search\":\"Alpha\"}", milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Alpha")
    }
}
