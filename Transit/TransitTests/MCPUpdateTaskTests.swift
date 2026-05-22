#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// swiftlint:disable file_length
// swiftlint:disable type_body_length

/// Tests for the MCP `update_task` tool handler, including milestone assignment
/// and the T-531 fix for save-failure rollback.
@MainActor @Suite(.serialized)
struct MCPUpdateTaskTests {

    @Test func setMilestoneByDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": milestoneDisplayId]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Task")
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func clearMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        #expect(task.milestone != nil)

        let taskDisplayId = try #require(task.permanentDisplayId)
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "clearMilestone": true]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Task")
        #expect(task.milestone == nil)
    }

    @Test func milestoneProjectMismatchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: projectA
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: projectB
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": milestoneDisplayId]
        ))

        #expect(try MCPTestHelpers.isError(response))
        // T-531: After error, task must not have a dirty milestone reference
        #expect(task.milestone == nil, "Task milestone should remain nil after failed update")
    }

    @Test func milestoneNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": 999]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - clearMilestone Type Validation [T-1060]

    /// T-1060: A `clearMilestone` value that is a string must be rejected with
    /// an error. Previously the malformed value was silently ignored and the
    /// milestone remained assigned, returning a misleading success response.
    @Test func clearMilestoneStringValueReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "clearMilestone": "true"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned after rejected request")
    }

    /// T-1060: A numeric `clearMilestone` value must be rejected.
    @Test func clearMilestoneNumericValueReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "clearMilestone": 1]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned after rejected request")
    }

    /// T-1060: An explicit `clearMilestone:false` must be accepted as a no-op.
    @Test func clearMilestoneFalseIsAcceptedAsNoOp() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "clearMilestone": false]
        ))

        #expect(try !MCPTestHelpers.isError(response), "clearMilestone:false should succeed")
        #expect(task.milestone?.id == milestone.id, "Milestone should remain assigned when clearMilestone is false")
    }

    /// T-531 regression: handleUpdateTask must not leave unsaved in-memory changes
    /// when the milestone assignment path errors out. Before the fix, setMilestone
    /// saved independently of the final save(), so a mid-handler error could leave
    /// dirty state on the shared context.
    @Test func doesNotLeakDirtyStateOnMilestoneError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: projectA
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: projectB
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        // Attempt assignment with project mismatch — should fail
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": milestoneDisplayId]
        ))

        #expect(try MCPTestHelpers.isError(response))

        // The context should have no pending changes after the error
        #expect(!env.context.hasChanges, "Context should not have dirty state after failed update_task")
        #expect(task.milestone == nil, "Task milestone should be nil after failed cross-project assignment")
    }

    // MARK: - T-650 Phase 4: Field Updates

    /// Round-trips a JSON string through JSONSerialization so non-string values
    /// (numbers, booleans) materialize as NSNumber, matching what `IntentHelpers.parseJSON`
    /// delivers to handlers.
    private static func jsonRoundTrip(_ json: String) throws -> [String: Any] {
        let data = try #require(json.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Name (AC 1.x)

    @Test func updateName_setsTrimmedName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": "  hello  "]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "hello")
        #expect(task.name == "hello")
    }

    @Test func updateName_rejectsEmpty() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": ""]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.name == "Original")
    }

    @Test func updateName_rejectsWhitespaceOnly() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": "   "]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.name == "Original")
    }

    @Test func updateName_rejectsNonString() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let args = try Self.jsonRoundTrip("{\"displayId\": \(taskDisplayId), \"name\": 42}")
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task", arguments: args
        ))

        #expect(try MCPTestHelpers.isError(response))
        let message = try MCPTestHelpers.errorText(response)
        #expect(message.contains("name"), "Expected name-specific error, got: \(message)")
        #expect(task.name == "Original")
    }

    // MARK: - Description (AC 2.x)

    @Test func updateDescription_setsTrimmed() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "description": "  text  "]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] as? String == "text")
        #expect(task.taskDescription == "text")
    }

    @Test func updateDescription_emptyClears() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "current", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "description": ""]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] == nil, "Response should omit description when cleared")
        #expect(task.taskDescription == nil)
    }

    @Test func updateDescription_whitespaceClears() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "current", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "description": "   "]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] == nil, "Response should omit description when cleared")
        #expect(task.taskDescription == nil)
    }

    @Test func updateDescription_rejectsNonString() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "current", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let args = try Self.jsonRoundTrip("{\"displayId\": \(taskDisplayId), \"description\": 42}")
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task", arguments: args
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.taskDescription == "current")
    }

    // MARK: - Type (AC 3.x)

    @Test func updateType_setsValidType() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "type": "feature"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["type"] as? String == "feature")
        #expect(task.type == .feature)
    }

    @Test func updateType_rejectsInvalidValue() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "type": "epic"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.type == .bug)
    }

    @Test func updateType_rejectsNonString() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let args = try Self.jsonRoundTrip("{\"displayId\": \(taskDisplayId), \"type\": 1}")
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task", arguments: args
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.type == .bug)
    }

    // MARK: - Metadata (AC 4.x)

    @Test func updateMetadata_replacesEntireDict() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1", "b": "2"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "metadata": ["c": "3"]]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let metadata = try #require(result["metadata"] as? [String: String])
        #expect(metadata == ["c": "3"])
        #expect(task.metadata == ["c": "3"])
    }

    @Test func updateMetadata_emptyDictClears() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "metadata": [String: String]()]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["metadata"] == nil, "Response should omit metadata when cleared")
        #expect(task.metadata.isEmpty)
    }

    @Test func updateMetadata_rejectsNonObject() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "metadata": "string"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(task.metadata == ["a": "1"])
    }

    @Test func updateMetadata_rejectsNonStringValues() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        // Round-trip via JSON so the `1` becomes NSNumber, not Swift Int.
        let args = try Self.jsonRoundTrip(
            "{\"displayId\": \(taskDisplayId), \"metadata\": {\"a\": 1}}"
        )
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task", arguments: args
        ))

        #expect(try MCPTestHelpers.isError(response))
        let message = try MCPTestHelpers.errorText(response)
        #expect(message == "metadata values must be strings", "Got: \(message)")
        #expect(task.metadata == ["a": "1"])
    }

    // MARK: - Omission Preservation (AC 1.4, 2.4, 3.4, 4.5)

    @Test func omittingNamePreservesIt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "X", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "description": "ignored"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "X")
        #expect(task.name == "X")
    }

    @Test func omittingDescriptionPreservesIt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "current", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        // Update something other than description
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": "Renamed"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] as? String == "current")
        #expect(task.taskDescription == "current")
    }

    @Test func omittingTypePreservesIt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": "Renamed"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["type"] as? String == "bug")
        #expect(task.type == .bug)
    }

    @Test func omittingMetadataPreservesIt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": "Renamed"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let metadata = try #require(result["metadata"] as? [String: String])
        #expect(metadata == ["a": "1"])
        #expect(task.metadata == ["a": "1"])
    }

    // MARK: - Atomicity (AC 5.x)

    @Test func updateMultipleFields_allAppliedAtomically() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: "old", type: .bug, project: project,
            metadata: ["a": "1"]
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": taskDisplayId,
                "name": "Renamed",
                "description": "new desc",
                "type": "chore",
                "metadata": ["new": "val"],
                "milestoneDisplayId": milestoneDisplayId
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Renamed")
        #expect(result["description"] as? String == "new desc")
        #expect(result["type"] as? String == "chore")

        #expect(task.name == "Renamed")
        #expect(task.taskDescription == "new desc")
        #expect(task.type == .chore)
        #expect(task.metadata == ["new": "val"])
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func updateMixed_invalidFieldRollsBackAll() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: "old", type: .bug, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        // Valid name + invalid type → whole call rejected
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": taskDisplayId,
                "name": "NewName",
                "type": "epic"  // invalid
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        // Nothing should have changed
        #expect(task.name == "Original")
        #expect(task.taskDescription == "old")
        #expect(task.type == .bug)
        #expect(task.metadata == ["a": "1"])
    }

    @Test func applyThrows_taskUntouched() async throws {
        // Drive an apply-time error via cross-project milestone mismatch
        // while also requesting field updates. The handler must roll back
        // any in-memory field mutations so the task fields are not modified.
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let task = try await env.taskService.createTask(
            name: "Original", description: "old", type: .bug, project: projectA,
            metadata: ["a": "1"]
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: projectB
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": taskDisplayId,
                "name": "NewName",
                "description": "new desc",
                "type": "chore",
                "metadata": ["new": "val"],
                "milestoneDisplayId": milestoneDisplayId  // mismatched project
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        // All field mutations must be rolled back
        #expect(task.name == "Original")
        #expect(task.taskDescription == "old")
        #expect(task.type == .bug)
        #expect(task.metadata == ["a": "1"])
        #expect(task.milestone == nil)
        #expect(!env.context.hasChanges, "Context should be clean after rollback")
    }

    // MARK: - No-op + Unknown Fields (AC 6.x)

    @Test func identifierOnly_doesNotSave_returnsCurrent() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "desc", type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let originalLastStatusChange = task.lastStatusChangeDate

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Task")
        #expect(result["description"] as? String == "desc")
        // No mutation → no timestamp tick from any side-effect
        #expect(task.lastStatusChangeDate == originalLastStatusChange)
        // Context should not have any pending changes either
        #expect(!env.context.hasChanges)
    }

    @Test func metadataEmpty_isMutation_triggersSave() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "metadata": [String: String]()]
        ))

        #expect(try !MCPTestHelpers.isError(response))
        #expect(task.metadata.isEmpty)
    }

    @Test func unknownFieldsIgnored_doNotBlockNoOp() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "desc", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "frob": "bar"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Task")
        #expect(result["description"] as? String == "desc")
        #expect(task.name == "Task")
    }

    // MARK: - Milestone Parity (AC 7.x)

    @Test func updateMilestoneAndName_singleSave() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": taskDisplayId,
                "name": "Renamed",
                "milestoneDisplayId": milestoneDisplayId
            ]
        ))

        #expect(try !MCPTestHelpers.isError(response))
        #expect(task.name == "Renamed")
        #expect(task.milestone?.id == milestone.id)
    }

    /// Documents that clearMilestone on an already-unassigned task is treated
    /// as a (redundant) save — acceptable per the design.
    @Test func clearMilestone_onAlreadyUnassigned_savesAnyway() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        #expect(task.milestone == nil)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "clearMilestone": true]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["milestone"] == nil, "Response should omit milestone when nil")
        #expect(task.milestone == nil)
    }

    // MARK: - Response Shape (AC 9.1)

    @Test func responseOmitsClearedDescriptionAndMetadata() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "old", type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": taskDisplayId,
                "description": "",
                "metadata": [String: String]()
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] == nil)
        #expect(result["metadata"] == nil)
    }

    @Test func responseExcludesCommentsAndDateFields() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "desc", type: .feature, project: project
        )
        _ = try env.commentService.addComment(
            to: task, content: "First", authorName: "Tester", isAgent: false
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "name": "Renamed"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["comments"] == nil)
        #expect(result["creationDate"] == nil)
        #expect(result["lastStatusChangeDate"] == nil)
        #expect(result["completionDate"] == nil)
    }

    // MARK: - Schema (AC 8.2)

    @Test func toolsListIncludesNewUpdateTaskFields() {
        let schema = MCPToolDefinitions.updateTask.inputSchema
        let properties = try? #require(schema.properties)
        guard let properties else { return }

        #expect(properties["name"] != nil)
        #expect(properties["description"] != nil)
        #expect(properties["type"] != nil)
        #expect(properties["metadata"] != nil)

        if let descProse = properties["description"]?.description {
            #expect(descProse.contains("clear"), "description prose should mention 'clear'; got: \(descProse)")
        } else {
            Issue.record("description property has no prose")
        }
        if let metaProse = properties["metadata"]?.description {
            #expect(
                metaProse.contains("clear") || metaProse.contains("{}"),
                "metadata prose should mention 'clear' or '{}'; got: \(metaProse)"
            )
        } else {
            Issue.record("metadata property has no prose")
        }
    }
}
// swiftlint:enable type_body_length

#endif
