import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-830: Milestone JSON/MCP paths must reject a present-but-non-string `status`
/// rather than silently treating it as absent. Covers `QueryMilestonesIntent` and
/// `UpdateMilestoneIntent`. The MCP equivalents live in
/// `MCPToolHandlerEnumValidationTests.swift`.
@MainActor @Suite(.serialized)
struct MilestoneStatusTypeValidationTests {

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
        displayId: Int
    ) -> Milestone {
        let milestone = Milestone(name: name, description: nil, project: project, displayID: .permanent(displayId))
        context.insert(milestone)
        return milestone
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - QueryMilestonesIntent

    @Test func queryNumericStatusReturnsInvalidStatus() throws {
        // status: 123 (integer) — must NOT be treated as "no filter" returning all milestones
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":123}", milestoneService: svc.milestone,
            projectService: svc.project)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func queryBooleanStatusReturnsInvalidStatus() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":true}", milestoneService: svc.milestone,
            projectService: svc.project)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func queryArrayStatusReturnsInvalidStatus() throws {
        // QueryMilestonesIntent only documents single-string status; arrays are not supported here.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":[\"open\"]}", milestoneService: svc.milestone,
            projectService: svc.project)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    // MARK: - UpdateMilestoneIntent

    @Test func updateNumericStatusRejectsBeforeApplyingNameChange() throws {
        // status: 123 (integer) is malformed; the intent must reject the request and
        // NOT silently rename the milestone while dropping the bogus status.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"status":123,"name":"Renamed"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")

        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.name == "v1.0", "Name was updated despite malformed status")
        #expect(milestone.statusRawValue == "open", "Status was changed despite malformed status input")
    }

    @Test func updateBooleanStatusReturnsInvalidStatus() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"status":false}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func updateNullStatusReturnsInvalidStatus() throws {
        // status: null — explicitly present but null. Treat as malformed rather than
        // silently dropping it.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"status":null,"name":"Renamed"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.name == "v1.0", "Name was updated despite malformed status")
    }
}
