import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1230: `UpdateMilestoneIntent` must reject a present-but-non-string `name`
/// (or `newName`) rather than silently dropping it and applying other update
/// fields. Mirrors the prior status validation work (T-830) and the project /
/// search / description / comment non-string rejection pattern.
@MainActor @Suite(.serialized)
struct MilestoneRenameTypeValidationTests {

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
        let milestone = Milestone(
            name: name, description: nil, project: project, displayID: .permanent(displayId)
        )
        context.insert(milestone)
        return milestone
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - displayId-identified path: "name" rename field

    @Test func updateNumericNameRejectsBeforeApplyingStatusChange() throws {
        // name: 123 (integer) is malformed; the intent must reject the request and
        // NOT silently apply the status change while dropping the bogus name.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":123,"status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")

        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.name == "v1.0", "Name should not have been changed")
        #expect(milestone.statusRawValue == "open", "Status should not have been changed despite malformed name")
    }

    @Test func updateBooleanNameReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":true}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")

        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.name == "v1.0")
    }

    @Test func updateNullNameReturnsInvalidInput() throws {
        // name: null — explicitly present but null. Treat as malformed rather than
        // silently dropping it.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":null,"status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.name == "v1.0")
        #expect(milestone.statusRawValue == "open")
    }

    @Test func updateArrayNameReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":["v2.0"]}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - name+project-identified path: "newName" rename field

    @Test func updateNumericNewNameRejectsRequest() throws {
        // When identified by name+project, the rename field is "newName".
        // A non-string newName must be rejected the same way.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"v1.0","project":"Test Project","newName":123,"status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.name == "v1.0")
        #expect(milestone.statusRawValue == "open", "Status should not have been changed")
    }

    @Test func updateBooleanNewNameReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"v1.0","project":"Test Project","newName":false}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - description field

    @Test func updateNumericDescriptionReturnsInvalidInput() throws {
        // description is a string-only update field. A non-string value must be
        // rejected, not silently dropped while other fields apply.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"description":123,"status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.statusRawValue == "open", "Status should not have been changed")
    }
}
