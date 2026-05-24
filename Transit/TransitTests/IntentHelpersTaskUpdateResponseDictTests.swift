import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for `IntentHelpers.taskUpdateResponseDict(_:)`. Verifies the AC 9.1
/// response shape: always-present keys, omitted-when-nil/empty keys, and the
/// explicit exclusion of `comments`, `creationDate`, `lastStatusChangeDate`,
/// and `completionDate`. [T-650]
@MainActor @Suite(.serialized)
struct IntentHelpersTaskUpdateResponseDictTests {

    // MARK: - Fixture

    private struct Fixture {
        let context: ModelContext
        let project: Project
    }

    private func makeFixture(includeProject: Bool = true) throws -> Fixture {
        let context = try TestModelContainer.newContext()
        let project = Project(
            name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000"
        )
        if includeProject {
            context.insert(project)
        }
        return Fixture(context: context, project: project)
    }

    private func makeTask(
        in context: ModelContext,
        name: String = "Sample Task",
        description: String? = nil,
        type: TaskType = .feature,
        project: Project?,
        milestone: Milestone? = nil,
        metadata: [String: String]? = nil,
        displayId: Int? = 42
    ) -> TransitTask {
        // TransitTask requires a project at init; we then overwrite to test the
        // unassigned-project case (the model field is optional even though the
        // initializer demands one).
        let placeholderProject = project ?? Project(
            name: "Placeholder", description: "", gitRepo: nil, colorHex: "#000000"
        )
        let displayID: DisplayID = displayId.map { .permanent($0) } ?? .provisional
        let task = TransitTask(
            name: name,
            description: description,
            type: type,
            project: placeholderProject,
            displayID: displayID,
            metadata: metadata
        )
        StatusEngine.initializeNewTask(task)
        if project == nil {
            task.project = nil
        }
        task.milestone = milestone
        context.insert(task)
        return task
    }

    private func makeMilestone(
        in context: ModelContext,
        name: String = "v1.0",
        project: Project,
        displayId: Int = 1
    ) -> Milestone {
        let milestone = Milestone(
            name: name, description: nil, project: project,
            displayID: .permanent(displayId)
        )
        context.insert(milestone)
        return milestone
    }

    // MARK: - Always-present keys

    @Test func allFieldsPopulated_includesEveryKey() throws {
        let fix = try makeFixture()
        let milestone = makeMilestone(in: fix.context, project: fix.project)
        let task = makeTask(
            in: fix.context,
            name: "Full Task",
            description: "A description",
            type: .bug,
            project: fix.project,
            milestone: milestone,
            metadata: ["key": "value"],
            displayId: 42
        )

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict["taskId"] as? String == task.id.uuidString)
        #expect(dict["name"] as? String == "Full Task")
        #expect(dict["type"] as? String == "bug")
        #expect(dict["status"] as? String == task.statusRawValue)
        #expect(dict["displayId"] as? Int == 42)
        #expect(dict["projectId"] as? String == fix.project.id.uuidString)
        #expect(dict["projectName"] as? String == "Test Project")
        #expect(dict["description"] as? String == "A description")
        #expect(dict["metadata"] as? [String: String] == ["key": "value"])
        let milestoneDict = dict["milestone"] as? [String: Any]
        #expect(milestoneDict != nil)
        #expect(milestoneDict?["name"] as? String == "v1.0")
    }

    @Test func nameAlwaysPresent() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, name: "Renamed", project: fix.project)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict["name"] as? String == "Renamed")
    }

    @Test func statusAlwaysPresent() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, project: fix.project)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        // Initialized via StatusEngine.initializeNewTask → idea.
        #expect(dict["status"] as? String == task.statusRawValue)
        #expect(dict["status"] as? String == "idea")
    }

    @Test func typeAlwaysPresent() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, type: .chore, project: fix.project)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict["type"] as? String == task.typeRawValue)
        #expect(dict["type"] as? String == "chore")
    }

    // MARK: - Conditionally-present keys (omitted when nil/empty)

    @Test func noDisplayId_omitsDisplayId() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, project: fix.project, displayId: nil)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict.keys.contains("displayId") == false)
    }

    @Test func noProject_omitsProjectKeys() throws {
        let fix = try makeFixture(includeProject: false)
        let task = makeTask(in: fix.context, project: nil)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict.keys.contains("projectId") == false)
        #expect(dict.keys.contains("projectName") == false)
        #expect(dict.keys.contains("milestone") == false)
    }

    @Test func noDescription_omitsDescription() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, description: nil, project: fix.project)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict.keys.contains("description") == false)
    }

    @Test func emptyDescription_omitsDescription() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, description: "", project: fix.project)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        // Per AC 9.1 the response must omit "" / null / {} for cleared fields.
        // The model stores taskDescription as String? — an explicit empty string
        // through this path must still be omitted by the response builder.
        #expect(dict.keys.contains("description") == false)
    }

    @Test func emptyMetadata_omitsMetadata() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, project: fix.project, metadata: nil)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(task.metadata.isEmpty)
        #expect(dict.keys.contains("metadata") == false)
    }

    @Test func nonEmptyMetadata_includesMetadata() throws {
        let fix = try makeFixture()
        let task = makeTask(
            in: fix.context, project: fix.project, metadata: ["a": "1"]
        )

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict["metadata"] as? [String: String] == ["a": "1"])
    }

    @Test func noMilestone_omitsMilestone() throws {
        let fix = try makeFixture()
        let task = makeTask(in: fix.context, project: fix.project, milestone: nil)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict.keys.contains("milestone") == false)
    }

    @Test func withMilestone_usesMilestoneInfoDict() throws {
        let fix = try makeFixture()
        let milestone = makeMilestone(in: fix.context, project: fix.project, displayId: 7)
        let task = makeTask(in: fix.context, project: fix.project, milestone: milestone)

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        // The milestone summary must match the existing milestoneInfoDict helper
        // verbatim — it is the single source of truth for the milestone shape.
        let expected = IntentHelpers.milestoneInfoDict(milestone)
        let actual = try #require(dict["milestone"] as? [String: Any])
        #expect(actual["milestoneId"] as? String == expected["milestoneId"] as? String)
        #expect(actual["name"] as? String == expected["name"] as? String)
        #expect(actual["displayId"] as? Int == expected["displayId"] as? Int)
        #expect(actual.keys.sorted() == expected.keys.sorted())
    }

    // MARK: - Excluded keys

    @Test func alwaysExcludesCommentsAndDateFields() throws {
        let fix = try makeFixture()
        let task = makeTask(
            in: fix.context,
            description: "Has comments and dates",
            project: fix.project,
            metadata: ["k": "v"]
        )
        // Populate excluded fields so the assertion is meaningful.
        let comment = Comment(
            content: "First comment", authorName: "Tester", isAgent: false, task: task
        )
        fix.context.insert(comment)
        task.completionDate = Date()
        task.lastStatusChangeDate = Date()

        let dict = IntentHelpers.taskUpdateResponseDict(task)

        #expect(dict.keys.contains("comments") == false)
        #expect(dict.keys.contains("creationDate") == false)
        #expect(dict.keys.contains("lastStatusChangeDate") == false)
        #expect(dict.keys.contains("completionDate") == false)
    }
}
