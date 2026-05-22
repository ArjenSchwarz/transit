import Foundation
import SwiftData
import Testing
@testable import Transit

// swiftlint:disable file_length
// swiftlint:disable type_body_length

@MainActor @Suite(.serialized)
struct UpdateTaskIntentTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let taskStore = InMemoryCounterStore()
        let taskAllocator = DisplayIDAllocator(store: taskStore)
        let milestoneStore = InMemoryCounterStore()
        let milestoneAllocator = DisplayIDAllocator(store: milestoneStore)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
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

    // MARK: - Milestone Assignment

    @Test func assignMilestoneByDisplayId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"displayId":10,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] as? String == task.id.uuidString)
        let milestoneInfo = parsed["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
        #expect(milestoneInfo?["displayId"] as? Int == 1)
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func assignMilestoneByName() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"displayId":10,"milestone":"v1.0"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        let milestoneInfo = parsed["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
        #expect(task.milestone != nil)
    }

    @Test func clearMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)

        let input = """
        {"displayId":10,"clearMilestone":true}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] as? String == task.id.uuidString)
        #expect(task.milestone == nil)
    }

    @Test func assignByTaskId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"taskId":"\(task.id.uuidString)","milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] as? String == task.id.uuidString)
        #expect(task.milestone != nil)
    }

    // MARK: - Error Cases

    @Test func unknownTaskReturnsTaskNotFound() throws {
        let svc = try makeServices()

        let input = """
        {"displayId":999,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "TASK_NOT_FOUND")
    }

    @Test func unknownMilestoneReturnsMilestoneNotFound() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"displayId":10,"milestoneDisplayId":999}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")
    }

    @Test func milestoneProjectMismatchReturnsError() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: beta, displayId: 1)
        makeTask(in: svc.context, name: "Task 1", project: alpha, displayId: 10)

        let input = """
        {"displayId":10,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_PROJECT_MISMATCH")
    }

    @Test func noTaskIdentifierReturnsInvalidInput() throws {
        let svc = try makeServices()

        let input = """
        {"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func malformedJSONReturnsInvalidInput() throws {
        let svc = try makeServices()

        let result = UpdateTaskIntent.execute(
            input: "not json", taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - clearMilestone Type Validation [T-1060]

    /// T-1060: A `clearMilestone` value that is a string must be rejected with
    /// INVALID_INPUT. Previously the malformed value was silently ignored and the
    /// milestone remained assigned, returning a misleading success response.
    @Test func clearMilestoneStringValueReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)

        let input = """
        {"displayId":10,"clearMilestone":"true"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned after rejected request")
    }

    /// T-1060: A numeric `clearMilestone` value must be rejected with INVALID_INPUT.
    @Test func clearMilestoneNumericValueReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)

        let input = """
        {"displayId":10,"clearMilestone":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned after rejected request")
    }

    /// T-1060: A `null` `clearMilestone` value must be rejected with INVALID_INPUT.
    @Test func clearMilestoneNullValueReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)

        let input = """
        {"displayId":10,"clearMilestone":null}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned after rejected request")
    }

    /// T-1060: An explicit `clearMilestone:false` must be accepted (no-op for clearing)
    /// and should not error. The milestone stays assigned because the caller did not
    /// request clearing, which is the documented behaviour.
    @Test func clearMilestoneFalseIsAcceptedAsNoOp() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)

        let input = """
        {"displayId":10,"clearMilestone":false}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] == nil, "clearMilestone:false should not error")
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned when clearMilestone is false")
    }

    // MARK: - T-650 Phase 5: Field Updates

    /// Round-trips a JSON string through JSONSerialization so non-string values
    /// (numbers, booleans) materialize as NSNumber, matching what
    /// `IntentHelpers.parseJSON` delivers to the intent's `execute`.
    private static func jsonRoundTrip(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Name (AC 1.x)

    @Test func updateName_setsTrimmedName() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)

        let input = """
        {"displayId":10,"name":"  hello  "}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "hello")
        #expect(task.name == "hello")
    }

    @Test func updateName_rejectsEmpty() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)

        let input = """
        {"displayId":10,"name":""}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.name == "Original")
    }

    @Test func updateName_rejectsWhitespaceOnly() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)

        let input = """
        {"displayId":10,"name":"   "}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.name == "Original")
    }

    @Test func updateName_rejectsNonString() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)

        let input = """
        {"displayId":10,"name":42}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let hint = parsed["hint"] as? String ?? ""
        #expect(hint.contains("name"), "Expected name-specific hint, got: \(hint)")
        #expect(task.name == "Original")
    }

    // MARK: - Description (AC 2.x)

    @Test func updateDescription_setsTrimmed() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)

        let input = """
        {"displayId":10,"description":"  text  "}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] as? String == "text")
        #expect(task.taskDescription == "text")
    }

    @Test func updateDescription_emptyClears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "current"

        let input = """
        {"displayId":10,"description":""}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] == nil, "Response should omit description when cleared")
        #expect(task.taskDescription == nil)
    }

    @Test func updateDescription_whitespaceClears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "current"

        let input = """
        {"displayId":10,"description":"   "}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] == nil, "Response should omit description when cleared")
        #expect(task.taskDescription == nil)
    }

    @Test func updateDescription_rejectsNonString() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "current"

        let input = """
        {"displayId":10,"description":42}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.taskDescription == "current")
    }

    // MARK: - Type (AC 3.x)

    @Test func updateType_setsValidType() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.type = .bug

        let input = """
        {"displayId":10,"type":"feature"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["type"] as? String == "feature")
        #expect(task.type == .feature)
    }

    @Test func updateType_rejectsInvalidValue() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.type = .bug

        let input = """
        {"displayId":10,"type":"epic"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.type == .bug)
    }

    @Test func updateType_rejectsNonString() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.type = .bug

        let input = """
        {"displayId":10,"type":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.type == .bug)
    }

    // MARK: - Metadata (AC 4.x)

    @Test func updateMetadata_replacesEntireDict() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.metadata = ["a": "1", "b": "2"]

        let input = """
        {"displayId":10,"metadata":{"c":"3"}}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        let metadata = try #require(parsed["metadata"] as? [String: String])
        #expect(metadata == ["c": "3"])
        #expect(task.metadata == ["c": "3"])
    }

    @Test func updateMetadata_emptyDictClears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"metadata":{}}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["metadata"] == nil, "Response should omit metadata when cleared")
        #expect(task.metadata.isEmpty)
    }

    @Test func updateMetadata_rejectsNonObject() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"metadata":"string"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect(task.metadata == ["a": "1"])
    }

    @Test func updateMetadata_rejectsNonStringValues() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"metadata":{"a":1}}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        let hint = parsed["hint"] as? String ?? ""
        #expect(hint == "metadata values must be strings", "Got: \(hint)")
        #expect(task.metadata == ["a": "1"])
    }

    // MARK: - Omission Preservation (AC 1.4, 2.4, 3.4, 4.5)

    @Test func omittingNamePreservesIt() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "X", project: project, displayId: 10)

        let input = """
        {"displayId":10,"description":"ignored"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "X")
        #expect(task.name == "X")
    }

    @Test func omittingDescriptionPreservesIt() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "current"

        let input = """
        {"displayId":10,"name":"Renamed"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] as? String == "current")
        #expect(task.taskDescription == "current")
    }

    @Test func omittingTypePreservesIt() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.type = .bug

        let input = """
        {"displayId":10,"name":"Renamed"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["type"] as? String == "bug")
        #expect(task.type == .bug)
    }

    @Test func omittingMetadataPreservesIt() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"name":"Renamed"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        let metadata = try #require(parsed["metadata"] as? [String: String])
        #expect(metadata == ["a": "1"])
        #expect(task.metadata == ["a": "1"])
    }

    // MARK: - Atomicity (AC 5.x)

    @Test func updateMultipleFields_allAppliedAtomically() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "Sprint 1", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)
        task.taskDescription = "old"
        task.type = .bug
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"name":"Renamed","description":"new desc",
        "type":"chore","metadata":{"new":"val"},"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "Renamed")
        #expect(parsed["description"] as? String == "new desc")
        #expect(parsed["type"] as? String == "chore")

        #expect(task.name == "Renamed")
        #expect(task.taskDescription == "new desc")
        #expect(task.type == .chore)
        #expect(task.metadata == ["new": "val"])
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func updateMixed_invalidFieldRollsBackAll() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)
        task.taskDescription = "old"
        task.type = .bug
        task.metadata = ["a": "1"]

        // Valid name + invalid type → whole call rejected
        let input = """
        {"displayId":10,"name":"NewName","type":"epic"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        // Nothing should have changed
        #expect(task.name == "Original")
        #expect(task.taskDescription == "old")
        #expect(task.type == .bug)
        #expect(task.metadata == ["a": "1"])
    }

    @Test func applyThrows_taskUntouched() throws {
        // Drive an apply-time error via cross-project milestone mismatch
        // while also requesting field updates. The handler must roll back
        // any in-memory field mutations so the task fields are not modified.
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        let milestone = makeMilestone(in: svc.context, name: "Sprint 1", project: beta, displayId: 1)
        let task = makeTask(in: svc.context, name: "Original", project: alpha, displayId: 10)
        task.taskDescription = "old"
        task.type = .bug
        task.metadata = ["a": "1"]
        _ = milestone
        // Persist setup so post-update `hasChanges` reflects only the update call,
        // not the test scaffolding's insert/mutation traffic.
        try svc.context.save()

        let input = """
        {"displayId":10,"name":"NewName","description":"new desc",
        "type":"chore","metadata":{"new":"val"},"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] != nil, "Expected error, got: \(parsed)")
        // All field mutations must be rolled back
        #expect(task.name == "Original")
        #expect(task.taskDescription == "old")
        #expect(task.type == .bug)
        #expect(task.metadata == ["a": "1"])
        #expect(task.milestone == nil)
        #expect(!svc.context.hasChanges, "Context should be clean after rollback")
    }

    // MARK: - No-op + Unknown Fields (AC 6.x)

    @Test func identifierOnly_doesNotSave_returnsCurrent() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "desc"
        task.metadata = ["a": "1"]
        try svc.context.save()
        let originalLastStatusChange = task.lastStatusChangeDate

        let input = """
        {"displayId":10}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "Task")
        #expect(parsed["description"] as? String == "desc")
        // No mutation → no timestamp tick from any side-effect
        #expect(task.lastStatusChangeDate == originalLastStatusChange)
        // Context should not have any pending changes either
        #expect(!svc.context.hasChanges)
    }

    @Test func metadataEmpty_isMutation_triggersSave() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"metadata":{}}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] == nil)
        #expect(task.metadata.isEmpty)
    }

    @Test func unknownFieldsIgnored_doNotBlockNoOp() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "desc"

        let input = """
        {"displayId":10,"frob":"bar"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["name"] as? String == "Task")
        #expect(parsed["description"] as? String == "desc")
        #expect(task.name == "Task")
    }

    // MARK: - Milestone Parity (AC 7.x)

    @Test func updateMilestoneAndName_singleSave() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "Sprint 1", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Original", project: project, displayId: 10)

        let input = """
        {"displayId":10,"name":"Renamed","milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] == nil)
        #expect(task.name == "Renamed")
        #expect(task.milestone?.id == milestone.id)
    }

    /// Documents that clearMilestone on an already-unassigned task is treated
    /// as a (redundant) save — acceptable per the design.
    @Test func clearMilestone_onAlreadyUnassigned_savesAnyway() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        #expect(task.milestone == nil)

        let input = """
        {"displayId":10,"clearMilestone":true}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestone"] == nil, "Response should omit milestone when nil")
        #expect(task.milestone == nil)
    }

    // MARK: - Response Shape (AC 9.1)

    @Test func responseOmitsClearedDescriptionAndMetadata() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "old"
        task.metadata = ["a": "1"]

        let input = """
        {"displayId":10,"description":"","metadata":{}}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["description"] == nil)
        #expect(parsed["metadata"] == nil)
    }

    @Test func responseExcludesCommentsAndDateFields() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Task", project: project, displayId: 10)
        task.taskDescription = "desc"

        let input = """
        {"displayId":10,"name":"Renamed"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["comments"] == nil)
        #expect(parsed["creationDate"] == nil)
        #expect(parsed["lastStatusChangeDate"] == nil)
        #expect(parsed["completionDate"] == nil)
    }

    // MARK: - Parameter Description (AC 8.2)

    @Test func inputParameterDescriptionContainsClearWording() {
        // The Input @Parameter description must document the empty-string-clears
        // semantic for description and the {} clears semantic for metadata so
        // that Shortcuts users see the same field guidance the MCP tool schema
        // provides. Asserted via the static test seam mirrored into the
        // @Parameter declaration.
        let description = UpdateTaskIntent.inputParameterDescription
        #expect(description.contains("description"), "Parameter description should mention 'description'")
        #expect(description.contains("metadata"), "Parameter description should mention 'metadata'")
        // Substring "clear" must appear at least twice (description and metadata)
        let occurrences = description.components(separatedBy: "clear").count - 1
        #expect(
            occurrences >= 2,
            "Parameter description should mention 'clear' at least twice; got \(occurrences) occurrence(s)"
        )
    }
}

// swiftlint:enable type_body_length
// swiftlint:enable file_length
