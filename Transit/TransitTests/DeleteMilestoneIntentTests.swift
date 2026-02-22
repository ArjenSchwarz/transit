import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct DeleteMilestoneIntentTests {

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

    private func makeTask(
        in context: ModelContext,
        name: String,
        project: Project,
        milestone: Milestone? = nil,
        displayId: Int
    ) -> TransitTask {
        let task = TransitTask(
            name: name, type: .feature, project: project, displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(task)
        task.milestone = milestone
        context.insert(task)
        return task
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Success Cases

    @Test func deleteByDisplayIdReturnsConfirmation() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"displayId":1}
        """

        let result = DeleteMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["deleted"] as? Bool == true)
        #expect(parsed["milestoneId"] as? String == milestone.id.uuidString)
        #expect(parsed["displayId"] as? Int == 1)
        #expect(parsed["name"] as? String == "v1.0")
        #expect(parsed["affectedTasks"] as? Int == 0)
    }

    @Test func deleteByMilestoneIdWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"milestoneId":"\(milestone.id.uuidString)"}
        """

        let result = DeleteMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["deleted"] as? Bool == true)
    }

    @Test func deleteReturnsAffectedTaskCount() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)
        makeTask(in: svc.context, name: "Task 2", project: project, milestone: milestone, displayId: 11)
        makeTask(in: svc.context, name: "Unrelated", project: project, displayId: 12)

        let input = """
        {"displayId":1}
        """

        let result = DeleteMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["affectedTasks"] as? Int == 2)
    }

    // MARK: - Error Cases

    @Test func unknownDisplayIdReturnsMilestoneNotFound() throws {
        let svc = try makeServices()

        let input = """
        {"displayId":999}
        """

        let result = DeleteMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")
    }

    @Test func noIdentifierReturnsInvalidInput() throws {
        let svc = try makeServices()

        let input = """
        {}
        """

        let result = DeleteMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func malformedJSONReturnsInvalidInput() throws {
        let svc = try makeServices()

        let result = DeleteMilestoneIntent.execute(
            input: "not json", milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }
}
