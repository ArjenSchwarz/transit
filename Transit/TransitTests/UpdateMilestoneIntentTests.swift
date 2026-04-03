import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct UpdateMilestoneIntentTests {

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

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Success Cases

    @Test func updateNameByDisplayId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":"v1.1"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "v1.1")
        #expect(parsed["displayId"] as? Int == 1)
    }

    @Test func updateStatusToDone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "done")
        #expect(parsed["previousStatus"] as? String == "open")
    }

    @Test func updateDescriptionByMilestoneId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"milestoneId":"\(milestone.id.uuidString)","description":"Updated description"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestoneId"] as? String == milestone.id.uuidString)
    }

    @Test func updateByNameAndProject() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "Alpha")
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"v1.0","project":"Alpha","status":"abandoned"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "abandoned")
        #expect(parsed["previousStatus"] as? String == "open")
    }

    @Test func reopenDoneMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .done)

        let input = """
        {"displayId":1,"status":"open"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "open")
        #expect(parsed["previousStatus"] as? String == "done")
    }

    // MARK: - Error Cases

    @Test func unknownDisplayIdReturnsMilestoneNotFound() throws {
        let svc = try makeServices()

        let input = """
        {"displayId":999,"name":"v2.0"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")
    }

    @Test func duplicateNameReturnsDuplicateMilestoneName() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let input = """
        {"displayId":2,"name":"v1.0"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "DUPLICATE_MILESTONE_NAME")
    }

    @Test func invalidStatusReturnsInvalidStatus() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"status":"flying"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func noIdentifierReturnsInvalidInput() throws {
        let svc = try makeServices()

        let input = """
        {"status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func fractionalDisplayIdReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        // 1.9 should NOT silently truncate to 1
        let input = """
        {"displayId":1.9,"name":"v2.0"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("integer") == true)
    }

    @Test func wholeNumberDoubleDisplayIdSucceeds() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        // 1.0 is a valid integer value even though JSON parses it as Double
        let input = """
        {"displayId":1.0,"name":"v1.1"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "v1.1")
    }

    @Test func malformedJSONReturnsInvalidInput() throws {
        let svc = try makeServices()

        let result = UpdateMilestoneIntent.execute(
            input: "not json", milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - Atomicity (T-626)

    @Test func statusNotAppliedWhenFieldUpdateFails() throws {
        // T-626: When status + name are both provided and the name update fails
        // (duplicate name), the status change must NOT be persisted.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        // Try to rename "v2.0" to "v1.0" (duplicate) while also changing status to "done"
        let input = """
        {"displayId":2,"name":"v1.0","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "DUPLICATE_MILESTONE_NAME")

        // The milestone's status must still be "open" — the status change should have been rolled back
        let milestone = try svc.milestone.findByDisplayID(2)
        #expect(milestone.statusRawValue == "open", "Status was applied despite field update failure")
    }

    @Test func statusNotAppliedWhenNameIsEmpty() throws {
        // T-626: When status + name are provided and the name is empty,
        // the status change must NOT be persisted.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":"   ","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] != nil)

        // The milestone's status must still be "open"
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.statusRawValue == "open", "Status was applied despite field update failure")
    }

    @Test func allFieldsAppliedAtomicallyOnSuccess() throws {
        // T-626: When status + name + description are all provided and valid,
        // everything should be applied together.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1,"name":"v2.0","description":"New description","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "v2.0")
        #expect(parsed["status"] as? String == "done")
        #expect(parsed["previousStatus"] as? String == "open")

        // Verify the description was also applied on the model
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.milestoneDescription == "New description")
    }
}
