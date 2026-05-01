import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-808: Regression tests verifying that malformed task identifiers
/// (`displayId` and `taskId`) are rejected with a field-specific
/// `INVALID_INPUT` instead of silently falling through to the other key
/// or to a generic `TASK_NOT_FOUND` error.
@MainActor @Suite(.serialized)
struct TaskIdentifierValidationTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let milestoneStore = InMemoryCounterStore()
        let milestoneAllocator = DisplayIDAllocator(store: milestoneStore)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Alpha") -> Project {
        let project = Project(
            name: name, description: "A test project",
            gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        in context: ModelContext,
        project: Project,
        displayId: Int,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(
            name: "Task \(displayId)", type: .feature, project: project,
            displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        context.insert(task)
        return task
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    // MARK: - UpdateStatusIntent: malformed displayId with valid taskId fallback

    @Test func updateStatusMalformedDisplayIdRejectsInsteadOfFallingBackToTaskId() throws {
        // When displayId is present but malformed, the intent must reject
        // with INVALID_INPUT for "displayId", not silently fall back to taskId.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project, displayId: 42)

        let input = """
        {"displayId":"not-an-int","taskId":"\(task.id.uuidString)","status":"in-progress"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: svc.task)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("displayId") == true)

        // Status must NOT have been updated via taskId fallback.
        let refetched = try svc.task.findByDisplayID(42)
        #expect(refetched.statusRawValue == "idea")
    }

    @Test func updateStatusNonStringTaskIdReturnsFieldSpecificError() throws {
        // When taskId is present but not a string (e.g. a number), reject
        // with a field-specific INVALID_INPUT for "taskId" rather than the
        // generic task-not-found message.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        let input = """
        {"taskId":123,"status":"in-progress"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: svc.task)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("taskId") == true)
    }

    @Test func updateStatusMalformedTaskIdStringReturnsFieldSpecificError() throws {
        // taskId provided as a string but not a valid UUID.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        let input = """
        {"taskId":"not-a-uuid","status":"in-progress"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: svc.task)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("taskId") == true)
    }

    @Test func updateStatusValidIdentifiersStillWork() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 7)

        let input = """
        {"displayId":7,"status":"in-progress"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: svc.task)

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "in-progress")

        let refetched = try svc.task.findByDisplayID(7)
        #expect(refetched.statusRawValue == "in-progress")
    }

    // MARK: - UpdateTaskIntent (via IntentHelpers.resolveTask)

    @Test func updateTaskMalformedDisplayIdRejectsInsteadOfFallingBackToTaskId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project, displayId: 5)
        let milestone = Milestone(name: "v1", project: project, displayID: .permanent(1))
        svc.context.insert(milestone)

        // Both displayId (malformed) and taskId (valid) are present.
        let input = """
        {"displayId":"not-an-int","taskId":"\(task.id.uuidString)","milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input,
            taskService: svc.task,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("displayId") == true)

        // Milestone assignment must NOT have happened via taskId fallback.
        let refetched = try svc.task.findByDisplayID(5)
        #expect(refetched.milestone == nil)
    }

    @Test func updateTaskNonStringTaskIdReturnsFieldSpecificError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        let input = """
        {"taskId":123,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input,
            taskService: svc.task,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("taskId") == true)
    }

    @Test func updateTaskMalformedTaskIdStringReturnsFieldSpecificError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        let input = """
        {"taskId":"not-a-uuid","milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input,
            taskService: svc.task,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("taskId") == true)
    }

    // MARK: - TaskService.resolveTask(from: dict) directly

    @Test func resolveTaskFromDictRejectsMalformedDisplayId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project, displayId: 99)

        // Malformed displayId, valid taskId fallback that should NOT win.
        let dict: [String: Any] = [
            "displayId": "not-an-int",
            "taskId": task.id.uuidString
        ]

        do {
            let resolved = try svc.task.resolveTask(from: dict)
            Issue.record(
                "Expected resolveTask to throw for malformed displayId, got \(resolved.id)"
            )
        } catch let error as TaskService.Error {
            // The bug: pre-fix, this falls through and returns the task via taskId.
            // After fix, it must throw a field-specific identifier error rather
            // than silently using the fallback.
            #expect(error != .taskNotFound, "Should reject the malformed key, not fall through")
        }
    }

    @Test func resolveTaskFromDictRejectsNonStringTaskId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        // taskId present but not a string.
        let dict: [String: Any] = ["taskId": 123]

        do {
            _ = try svc.task.resolveTask(from: dict)
            Issue.record("Expected resolveTask to throw for non-string taskId")
        } catch let error as TaskService.Error {
            // The bug: pre-fix, this throws .taskNotFound.
            // After fix, it must throw a field-specific identifier error.
            #expect(error != .taskNotFound, "Should reject malformed taskId, not throw generic not-found")
        }
    }

    @Test func resolveTaskFromDictRejectsMalformedTaskIdString() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        let dict: [String: Any] = ["taskId": "not-a-uuid"]

        do {
            _ = try svc.task.resolveTask(from: dict)
            Issue.record("Expected resolveTask to throw for malformed taskId string")
        } catch let error as TaskService.Error {
            // The bug: pre-fix, this throws .taskNotFound.
            // After fix, it must throw a field-specific identifier error.
            #expect(error != .taskNotFound, "Should reject malformed taskId, not throw generic not-found")
        }
    }

    @Test func resolveTaskFromDictMissingKeysThrowsTaskNotFound() throws {
        let svc = try makeServices()
        // Empty dictionary — neither key present.
        let dict: [String: Any] = [:]

        do {
            _ = try svc.task.resolveTask(from: dict)
            Issue.record("Expected resolveTask to throw taskNotFound")
        } catch let error as TaskService.Error {
            #expect(error == .taskNotFound)
        }
    }

}
