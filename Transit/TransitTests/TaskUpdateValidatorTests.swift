import Foundation
import SwiftData
import Testing
@testable import Transit

// swiftlint:disable file_length
// swiftlint:disable type_body_length

/// Tests for `TaskUpdateValidator.validate`, `.apply`, and `.strictStringMetadata`.
/// Mirrors the structure of `UpdateTaskIntentTests` (Swift Testing,
/// `@MainActor @Suite(.serialized)`). See specs/update-task-all-fields/design.md
/// for the validator contract and AC references. [T-650]
@MainActor @Suite(.serialized)
struct TaskUpdateValidatorTests {

    // MARK: - Fixture

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
        name: String = "Task 1",
        description: String? = nil,
        type: TaskType = .feature,
        project: Project,
        milestone: Milestone? = nil,
        metadata: [String: String]? = nil,
        displayId: Int = 10
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            description: description,
            type: type,
            project: project,
            displayID: .permanent(displayId),
            metadata: metadata
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

    /// Round-trips a Swift dictionary through JSONSerialization so non-string
    /// values (numbers, booleans) materialize as NSNumber, matching what
    /// `IntentHelpers.parseJSON` delivers to handlers. Used to exercise the
    /// strict metadata path which must reject NSNumber values.
    private func jsonRoundTrip(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func unwrapSuccess(
        _ result: Result<ValidatedTaskUpdate, TaskUpdateValidationError>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> ValidatedTaskUpdate {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)", sourceLocation: sourceLocation)
            throw TestFailure.unexpectedFailure
        }
    }

    private func unwrapFailure(
        _ result: Result<ValidatedTaskUpdate, TaskUpdateValidationError>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> TaskUpdateValidationError {
        switch result {
        case .success(let value):
            Issue.record("Expected failure, got success: \(value)", sourceLocation: sourceLocation)
            throw TestFailure.unexpectedSuccess
        case .failure(let error): return error
        }
    }

    private enum TestFailure: Error { case unexpectedSuccess; case unexpectedFailure }

    private func isInvalidInput(_ error: TaskUpdateValidationError, contains substring: String? = nil) -> Bool {
        if case .invalidInput(let message) = error {
            guard let substring else { return true }
            return message.contains(substring)
        }
        return false
    }

    // MARK: - Name (AC 1.1–1.4)

    @Test func validate_nameSet_trimsAndApplies() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["name": "  hello  "], task: task, milestoneService: svc.milestone
        )
        let update = try unwrapSuccess(result)
        #expect(update.name == "hello")
        #expect(update.hasChanges == true)
    }

    @Test func validate_nameEmpty_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["name": ""], task: task, milestoneService: svc.milestone
        )
        let error = try unwrapFailure(result)
        #expect(isInvalidInput(error), "Expected .invalidInput, got \(error)")
    }

    @Test func validate_nameWhitespaceOnly_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["name": "   "], task: task, milestoneService: svc.milestone
        )
        let error = try unwrapFailure(result)
        #expect(isInvalidInput(error), "Expected .invalidInput, got \(error)")
    }

    @Test func validate_nameNonString_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        // JSON `42` round-trips as NSNumber, which would fail `as? String`.
        let args = try jsonRoundTrip("{\"name\": 42}")
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let error = try unwrapFailure(result)
        #expect(isInvalidInput(error, contains: "name"), "Expected name-specific invalidInput, got \(error)")
    }

    // MARK: - Description (AC 2.1–2.4)

    @Test func validate_descriptionSet_trimsAndApplies() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["description": "  text  "], task: task, milestoneService: svc.milestone
        )
        let update = try unwrapSuccess(result)
        guard case .set(let value) = update.description else {
            Issue.record("Expected .set, got \(update.description)")
            return
        }
        #expect(value == "text")
        #expect(update.hasChanges == true)
    }

    @Test func validate_descriptionEmpty_clears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["description": ""], task: task, milestoneService: svc.milestone
        )
        let update = try unwrapSuccess(result)
        guard case .clear = update.description else {
            Issue.record("Expected .clear, got \(update.description)")
            return
        }
        #expect(update.hasChanges == true)
    }

    @Test func validate_descriptionWhitespace_clears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["description": "   "], task: task, milestoneService: svc.milestone
        )
        let update = try unwrapSuccess(result)
        guard case .clear = update.description else {
            Issue.record("Expected .clear, got \(update.description)")
            return
        }
        #expect(update.hasChanges == true)
    }

    @Test func validate_descriptionNonString_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let args = try jsonRoundTrip("{\"description\": 42}")
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let error = try unwrapFailure(result)
        #expect(
            isInvalidInput(error, contains: "description"),
            "Expected description-specific invalidInput, got \(error)"
        )
    }

    // MARK: - Type (AC 3.1–3.4)

    @Test func validate_typeValid_setsLowercase() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, type: .bug, project: project)

        let result = TaskUpdateValidator.validate(
            ["type": "feature"], task: task, milestoneService: svc.milestone
        )
        let update = try unwrapSuccess(result)
        #expect(update.type == .feature)
        #expect(update.hasChanges == true)
    }

    @Test func validate_typeInvalid_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["type": "epic"], task: task, milestoneService: svc.milestone
        )
        let error = try unwrapFailure(result)
        #expect(isInvalidInput(error), "Expected .invalidInput, got \(error)")
    }

    @Test func validate_typeNonString_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let args = try jsonRoundTrip("{\"type\": 1}")
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let error = try unwrapFailure(result)
        #expect(isInvalidInput(error, contains: "type"), "Expected type-specific invalidInput, got \(error)")
    }

    /// AC 3.1 requires exact lowercase match with no canonicalization. Guard
    /// against a future well-intentioned case-insensitive change by asserting
    /// that capitalised type strings (`Feature`, `BUG`, etc.) are rejected.
    @Test func validate_typeCapitalized_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        for value in ["Feature", "BUG", "Chore"] {
            let result = TaskUpdateValidator.validate(
                ["type": value], task: task, milestoneService: svc.milestone
            )
            let error = try unwrapFailure(result)
            #expect(
                isInvalidInput(error, contains: value),
                "Expected capitalized type '\(value)' to be rejected with invalidInput, got \(error)"
            )
        }
    }

    // MARK: - Metadata (AC 4.1–4.4)

    @Test func validate_metadataDict_replaces() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let args: [String: Any] = ["metadata": ["a": "1", "b": "2"]]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        guard case .set(let dict) = update.metadata else {
            Issue.record("Expected .set, got \(update.metadata)")
            return
        }
        #expect(dict == ["a": "1", "b": "2"])
        #expect(update.hasChanges == true)
    }

    @Test func validate_metadataEmptyDict_clears() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let args: [String: Any] = ["metadata": [String: String]()]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        guard case .clear = update.metadata else {
            Issue.record("Expected .clear, got \(update.metadata)")
            return
        }
        #expect(update.hasChanges == true)
    }

    @Test func validate_metadataNonObject_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let result = TaskUpdateValidator.validate(
            ["metadata": "string"], task: task, milestoneService: svc.milestone
        )
        let error = try unwrapFailure(result)
        #expect(isInvalidInput(error, contains: "metadata"), "Expected metadata-specific invalidInput, got \(error)")
    }

    @Test func validate_metadataNonStringValues_rejects() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        // {"metadata": {"a": 123}} — 123 round-trips as NSNumber and must fail strict cast.
        let args = try jsonRoundTrip("{\"metadata\": {\"a\": 123}}")
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let error = try unwrapFailure(result)
        if case .invalidInput(let message) = error {
            #expect(message == "metadata values must be strings", "Expected literal AC 4.4 message, got: \(message)")
        } else {
            Issue.record("Expected .invalidInput, got \(error)")
        }
    }

    // MARK: - Milestone (parity with existing handler)

    @Test func validate_setMilestoneByDisplayId_returnsAssignAction() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, project: project)

        let args: [String: Any] = ["milestoneDisplayId": 1]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        guard case .assign(let assigned) = update.milestoneAction else {
            Issue.record("Expected .assign, got \(String(describing: update.milestoneAction))")
            return
        }
        #expect(assigned.id == milestone.id)
        #expect(update.hasChanges == true)
    }

    @Test func validate_setMilestoneByDisplayId_notFound_returnsMilestoneNotFound() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let args: [String: Any] = ["milestoneDisplayId": 999]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let error = try unwrapFailure(result)
        if case .milestoneNotFound(let message) = error {
            // Match MCP handler's existing literal exactly.
            #expect(message == "No milestone with displayId 999")
        } else {
            Issue.record("Expected .milestoneNotFound, got \(error)")
        }
    }

    @Test func validate_setMilestoneByDisplayId_wrongProject_returnsMilestoneProjectMismatch() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: beta, displayId: 1)
        let task = makeTask(in: svc.context, project: alpha)

        let args: [String: Any] = ["milestoneDisplayId": 1]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let error = try unwrapFailure(result)
        if case .milestoneProjectMismatch = error {
            // Expected
        } else {
            Issue.record("Expected .milestoneProjectMismatch, got \(error)")
        }
    }

    @Test func validate_clearMilestone_returnsClearAction() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, project: project, milestone: milestone)

        let args: [String: Any] = ["clearMilestone": true]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        guard case .clear = update.milestoneAction else {
            Issue.record("Expected .clear, got \(String(describing: update.milestoneAction))")
            return
        }
        #expect(update.hasChanges == true)
    }

    @Test func validate_clearMilestoneOnUnassigned_stillReturnsClear() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        // Task without milestone.
        let task = makeTask(in: svc.context, project: project)
        #expect(task.milestone == nil)

        let args: [String: Any] = ["clearMilestone": true]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        guard case .clear = update.milestoneAction else {
            Issue.record("Expected .clear even on unassigned task, got \(String(describing: update.milestoneAction))")
            return
        }
        #expect(update.hasChanges == true)
    }

    // MARK: - hasChanges semantics (AC 5.1, 7.1, 7.2)

    @Test func validate_identifierOnlyArgs_hasChangesFalse() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project, displayId: 10)

        let args: [String: Any] = ["taskId": task.id.uuidString]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        #expect(update.hasChanges == false)
    }

    @Test func validate_unknownFieldsIgnored_stillHasChangesFalse() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project)

        let args: [String: Any] = [
            "taskId": task.id.uuidString,
            "frob": "bar",
            "nmae": "typo"
        ]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        #expect(update.hasChanges == false)
    }

    // MARK: - strictStringMetadata (AC 4.4)

    @Test func strictStringMetadata_dictOfStrings_succeeds() throws {
        let result = TaskUpdateValidator.strictStringMetadata(from: ["a": "1", "b": "2"])
        switch result {
        case .success(let change):
            guard case .set(let dict) = change else {
                Issue.record("Expected .set, got \(change)")
                return
            }
            #expect(dict == ["a": "1", "b": "2"])
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)")
        }
    }

    @Test func strictStringMetadata_NSNumberValue_rejects() throws {
        let args = try jsonRoundTrip("{\"a\": 1}")
        // `args` is a `[String: Any]` whose value is NSNumber.
        let result = TaskUpdateValidator.strictStringMetadata(from: args)
        switch result {
        case .success(let change):
            Issue.record("Expected failure for NSNumber value, got success: \(change)")
        case .failure(let error):
            if case .invalidInput(let message) = error {
                #expect(
                    message == "metadata values must be strings",
                    "Expected literal AC 4.4 message, got: \(message)"
                )
            } else {
                Issue.record("Expected .invalidInput, got \(error)")
            }
        }
    }

    @Test func strictStringMetadata_nilOrMissing_returnsNoChange() throws {
        let result = TaskUpdateValidator.strictStringMetadata(from: nil)
        switch result {
        case .success(let change):
            guard case .noChange = change else {
                Issue.record("Expected .noChange, got \(change)")
                return
            }
        case .failure(let error):
            Issue.record("Expected .noChange success, got failure: \(error)")
        }
    }

    @Test func strictStringMetadata_nonDictInput_rejects() throws {
        let result = TaskUpdateValidator.strictStringMetadata(from: "not a dict")
        switch result {
        case .success(let change):
            Issue.record("Expected failure for non-dict, got success: \(change)")
        case .failure(let error):
            #expect(isInvalidInput(error, contains: "metadata"), "Expected metadata invalidInput, got \(error)")
        }
    }

    @Test func strictStringMetadata_emptyDict_returnsClear() throws {
        let result = TaskUpdateValidator.strictStringMetadata(from: [String: String]())
        switch result {
        case .success(let change):
            guard case .clear = change else {
                Issue.record("Expected .clear, got \(change)")
                return
            }
        case .failure(let error):
            Issue.record("Expected .clear success, got failure: \(error)")
        }
    }

    // MARK: - apply (AC 5.1, 7.1, 7.2)

    @Test func apply_setsNameDescriptionTypeMetadata_inMemory_noSaveSideEffect() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, name: "Old", type: .bug, project: project)
        // Flush any previous unsaved state (from insertion). The fixture inserts but
        // does not save; baseline for the test is "context already dirty from insert".
        try svc.context.save()
        #expect(svc.context.hasChanges == false)

        let args: [String: Any] = [
            "name": "  New  ",
            "description": "  Body  ",
            "type": "feature",
            "metadata": ["k": "v"]
        ]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)

        try TaskUpdateValidator.apply(
            update, to: task,
            taskService: svc.task, milestoneService: svc.milestone
        )

        #expect(task.name == "New")
        #expect(task.taskDescription == "Body")
        #expect(task.type == .feature)
        #expect(task.metadata == ["k": "v"])
        // apply must not save — the context should still be dirty.
        #expect(svc.context.hasChanges == true)
    }

    @Test func apply_clearDescriptionAndMetadata_sets_nilAndEmpty() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(
            in: svc.context,
            description: "old description",
            project: project,
            metadata: ["a": "1"]
        )
        try svc.context.save()

        let args: [String: Any] = [
            "description": "",
            "metadata": [String: String]()
        ]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)

        try TaskUpdateValidator.apply(
            update, to: task,
            taskService: svc.task, milestoneService: svc.milestone
        )

        #expect(task.taskDescription == nil)
        #expect(task.metadata.isEmpty)
    }

    @Test func apply_noChangeFields_areUntouched() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(
            in: svc.context, name: "Keep", description: "Keep desc",
            type: .chore, project: project, metadata: ["k": "v"]
        )
        try svc.context.save()

        // Empty args — should produce no-op update with hasChanges == false.
        let result = TaskUpdateValidator.validate([:], task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)
        #expect(update.hasChanges == false)

        // Even if a caller chose to call apply, nothing should change.
        try TaskUpdateValidator.apply(
            update, to: task,
            taskService: svc.task, milestoneService: svc.milestone
        )

        #expect(task.name == "Keep")
        #expect(task.taskDescription == "Keep desc")
        #expect(task.type == .chore)
        #expect(task.metadata == ["k": "v"])
    }

    @Test func apply_milestoneAssign_callsSetMilestone_inMemory() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, project: project)
        try svc.context.save()

        let args: [String: Any] = ["milestoneDisplayId": 1]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)

        try TaskUpdateValidator.apply(
            update, to: task,
            taskService: svc.task, milestoneService: svc.milestone
        )

        #expect(task.milestone?.id == milestone.id)
        #expect(svc.context.hasChanges == true)
    }

    @Test func apply_milestoneClear_callsSetMilestone_withNil() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, project: project, milestone: milestone)
        try svc.context.save()

        let args: [String: Any] = ["clearMilestone": true]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)

        try TaskUpdateValidator.apply(
            update, to: task,
            taskService: svc.task, milestoneService: svc.milestone
        )

        #expect(task.milestone == nil)
        #expect(svc.context.hasChanges == true)
    }

    /// Induce a service-layer throw mid-apply and confirm:
    /// 1. `apply` propagates the throw (does not catch).
    /// 2. The caller can recover by calling `taskService.rollback()` after which
    ///    the pre-apply state is restored.
    ///
    /// The scenario: validator returns an `assign` action for a milestone whose
    /// project we mutate after validation but before apply, forcing
    /// `MilestoneService.setMilestone` to throw `projectMismatch`. The earlier
    /// in-memory field mutations from `taskService.updateTask` should then be
    /// rolled back.
    @Test func apply_milestoneThrows_propagates_callerCanRollback() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)
        let task = makeTask(
            in: svc.context, name: "Original", description: "Original desc",
            type: .bug, project: alpha
        )
        // Persist the baseline so rollback has a clean state to revert to.
        try svc.context.save()

        // Validate against the matching project so the validator succeeds.
        let args: [String: Any] = [
            "name": "Renamed",
            "description": "New desc",
            "milestoneDisplayId": 1
        ]
        let result = TaskUpdateValidator.validate(args, task: task, milestoneService: svc.milestone)
        let update = try unwrapSuccess(result)

        // Now break the precondition: move the milestone to a different project so
        // setMilestone throws projectMismatch mid-apply.
        milestone.project = beta
        try svc.context.save()

        // apply should throw because milestone's project no longer matches task's.
        var threw = false
        do {
            try TaskUpdateValidator.apply(
                update, to: task,
                taskService: svc.task, milestoneService: svc.milestone
            )
        } catch {
            threw = true
        }
        #expect(threw, "Expected apply to throw when milestone setter rejects")

        // At this point the task may have been mutated in memory by the earlier
        // updateTask call. Caller rolls back to discard partial state.
        svc.task.rollback()

        #expect(task.name == "Original", "Name should revert after rollback")
        #expect(task.taskDescription == "Original desc", "Description should revert after rollback")
    }
}

// swiftlint:enable type_body_length
// swiftlint:enable file_length
