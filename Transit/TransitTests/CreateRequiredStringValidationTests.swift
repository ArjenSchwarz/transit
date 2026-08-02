import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression coverage for T-1598: required create fields must distinguish a
/// missing key from a present value with the wrong JSON type.
@MainActor @Suite(.serialized)
struct CreateRequiredStringValidationTests {

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
        let projectModel: Project
    }

    private let nonStringValues: [(label: String, value: Any)] = [
        ("numeric", 123),
        ("boolean", true),
        ("array", ["unexpected"]),
        ("object", ["unexpected": true]),
        ("null", NSNull())
    ]

    private func makeServices() throws -> Services {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let project = Project(
            name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context,
            projectModel: project
        )
    }

    private func jsonInput(_ fields: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - MCP create_task

#if os(macOS)
    @Test func mcpCreateTaskRejectsNonStringNameAndTypeWithoutMutation() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        for entry in nonStringValues {
            let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "create_task",
                arguments: [
                    "name": entry.value,
                    "type": "feature",
                    "projectId": project.id.uuidString
                ]
            ))
            #expect(try MCPTestHelpers.isError(response))
            #expect(try MCPTestHelpers.errorText(response) == "name must be a string")
        }

        for entry in nonStringValues {
            let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "create_task",
                arguments: [
                    "name": "Task",
                    "type": entry.value,
                    "projectId": project.id.uuidString
                ]
            ))
            #expect(try MCPTestHelpers.isError(response))
            #expect(try MCPTestHelpers.errorText(response) == "type must be a string")
        }

        let missingName = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["type": "feature", "projectId": project.id.uuidString]
        ))
        #expect(try MCPTestHelpers.errorText(missingName) == "Missing required argument: name")

        let invalidType = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "epic", "projectId": project.id.uuidString]
        ))
        #expect(try MCPTestHelpers.errorText(invalidType).hasPrefix("Invalid type: epic."))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Malformed create_task requests must not create tasks")
    }
#endif

    // MARK: - CreateTaskIntent

    @Test func createTaskIntentRejectsNonStringNameAndTypeWithoutMutation() async throws {
        let services = try makeServices()

        for entry in nonStringValues {
            let input = try jsonInput([
                "name": entry.value,
                "type": "feature",
                "projectId": services.projectModel.id.uuidString
            ])
            let result = await CreateTaskIntent.execute(
                input: input, taskService: services.task, projectService: services.project
            )
            let parsed = try parseJSON(result)
            #expect(parsed["error"] as? String == "INVALID_INPUT")
            #expect(parsed["hint"] as? String == "name must be a string")
        }

        for entry in nonStringValues {
            let input = try jsonInput([
                "name": "Task",
                "type": entry.value,
                "projectId": services.projectModel.id.uuidString
            ])
            let result = await CreateTaskIntent.execute(
                input: input, taskService: services.task, projectService: services.project
            )
            let parsed = try parseJSON(result)
            #expect(parsed["error"] as? String == "INVALID_INPUT")
            #expect(parsed["hint"] as? String == "type must be a string")
        }

        let missingName = await CreateTaskIntent.execute(
            input: try jsonInput(["type": "feature", "projectId": services.projectModel.id.uuidString]),
            taskService: services.task,
            projectService: services.project
        )
        #expect(try parseJSON(missingName)["hint"] as? String == "Missing required field: name")

        let invalidType = await CreateTaskIntent.execute(
            input: try jsonInput([
                "name": "Task", "type": "epic", "projectId": services.projectModel.id.uuidString
            ]),
            taskService: services.task,
            projectService: services.project
        )
        let invalidTypeJSON = try parseJSON(invalidType)
        #expect(invalidTypeJSON["error"] as? String == "INVALID_TYPE")
        #expect(invalidTypeJSON["hint"] as? String == "Unknown type: epic")

        #expect(try services.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    // MARK: - MCP create_milestone

#if os(macOS)
    @Test func mcpCreateMilestoneRejectsNonStringNameWithoutMutation() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        for entry in nonStringValues {
            let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "create_milestone",
                arguments: ["name": entry.value, "projectId": project.id.uuidString]
            ))
            #expect(try MCPTestHelpers.isError(response))
            #expect(try MCPTestHelpers.errorText(response) == "name must be a string")
        }

        let missingName = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["projectId": project.id.uuidString]
        ))
        #expect(try MCPTestHelpers.errorText(missingName) == "Missing required argument: name")

        let milestones = try env.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Malformed create_milestone requests must not create milestones")
    }
#endif

    // MARK: - CreateMilestoneIntent

    @Test func createMilestoneIntentRejectsNonStringNameWithoutMutation() async throws {
        let services = try makeServices()

        for entry in nonStringValues {
            let input = try jsonInput([
                "name": entry.value,
                "projectId": services.projectModel.id.uuidString
            ])
            let result = await CreateMilestoneIntent.execute(
                input: input,
                milestoneService: services.milestone,
                projectService: services.project
            )
            let parsed = try parseJSON(result)
            #expect(parsed["error"] as? String == "INVALID_INPUT")
            #expect(parsed["hint"] as? String == "name must be a string")
        }

        let missingName = await CreateMilestoneIntent.execute(
            input: try jsonInput(["projectId": services.projectModel.id.uuidString]),
            milestoneService: services.milestone,
            projectService: services.project
        )
        #expect(try parseJSON(missingName)["hint"] as? String == "Missing required field: name")

        let milestones = try services.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Malformed create milestone requests must not create milestones")
    }
}
