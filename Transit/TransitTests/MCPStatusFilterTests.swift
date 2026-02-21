#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPStatusFilterTests {

    // MARK: - Multi-status inclusion

    @Test func queryWithStatusArrayReturnsMatchingTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let ideaTask = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let planningTask = try await env.taskService.createTask(
            name: "Planning", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: planningTask, to: .planning)
        let specTask = try await env.taskService.createTask(
            name: "Spec", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: specTask, to: .planning)
        try env.taskService.updateStatus(task: specTask, to: .spec)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["idea", "planning"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let names = Set(results.compactMap { $0["name"] as? String })
        #expect(names == ["Idea", "Planning"])
    }

    @Test func queryWithSingleStatusStringStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let planningTask = try await env.taskService.createTask(
            name: "Planning", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: planningTask, to: .planning)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": "planning"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Planning")
    }

    // MARK: - Status exclusion

    @Test func queryWithNotStatusExcludesMatching() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Active", description: nil, type: .feature, project: project
        )
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .planning)
        try env.taskService.updateStatus(task: doneTask, to: .spec)
        try env.taskService.updateStatus(task: doneTask, to: .inProgress)
        try env.taskService.updateStatus(task: doneTask, to: .done)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["not_status": ["done", "abandoned"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Active")
    }

    // MARK: - Unfinished flag

    @Test func queryWithUnfinishedExcludesDoneAndAbandoned() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Active", description: nil, type: .feature, project: project
        )
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .planning)
        try env.taskService.updateStatus(task: doneTask, to: .spec)
        try env.taskService.updateStatus(task: doneTask, to: .inProgress)
        try env.taskService.updateStatus(task: doneTask, to: .done)
        let abandonedTask = try await env.taskService.createTask(
            name: "Abandoned", description: nil, type: .bug, project: project
        )
        try env.taskService.updateStatus(task: abandonedTask, to: .abandoned)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["unfinished": true]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Active")
    }

    @Test func unfinishedMergesWithExplicitNotStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let planningTask = try await env.taskService.createTask(
            name: "Planning", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: planningTask, to: .planning)

        // unfinished=true excludes done+abandoned, not_status adds planning to exclusion
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["unfinished": true, "not_status": ["planning"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Idea")
    }

    // MARK: - Combined inclusion and exclusion

    @Test func statusAndNotStatusComposeConjunctively() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let planningTask = try await env.taskService.createTask(
            name: "Planning", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: planningTask, to: .planning)

        // Include idea+planning, but exclude planning → only idea remains
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["idea", "planning"], "not_status": ["planning"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Idea")
    }

    // MARK: - Edge cases

    @Test func contradictoryFiltersReturnEmpty() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .planning)
        try env.taskService.updateStatus(task: doneTask, to: .spec)
        try env.taskService.updateStatus(task: doneTask, to: .inProgress)
        try env.taskService.updateStatus(task: doneTask, to: .done)

        // status=done + unfinished=true → contradictory, should return empty
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["done"], "unfinished": true]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func emptyStatusArrayWithNonEmptyNotStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .planning)
        try env.taskService.updateStatus(task: doneTask, to: .spec)
        try env.taskService.updateStatus(task: doneTask, to: .inProgress)
        try env.taskService.updateStatus(task: doneTask, to: .done)

        // Empty status (treated as absent = all statuses) + not_status excludes done
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": [String](), "not_status": ["done"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Idea")
    }

    @Test func singleStringNotStatusStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .planning)
        try env.taskService.updateStatus(task: doneTask, to: .spec)
        try env.taskService.updateStatus(task: doneTask, to: .inProgress)
        try env.taskService.updateStatus(task: doneTask, to: .done)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["not_status": "done"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Idea")
    }

    @Test func emptyStatusArrayTreatedAsAbsent() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "A", description: nil, type: .feature, project: project
        )
        _ = try await env.taskService.createTask(
            name: "B", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": [String](), "not_status": [String]()]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

}

#endif
