import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression coverage for T-1991: a present `metadata` field must be a JSON
/// object. Non-object values must be rejected before task insertion instead of
/// being silently treated as omitted metadata.
@MainActor @Suite(.serialized)
struct CreateTaskMetadataShapeValidationTests {

    private struct IntentServices {
        let task: TaskService
        let project: ProjectService
        let context: ModelContext
        let projectModel: Project
    }

    private let nonObjectValues: [(label: String, value: Any)] = [
        ("string", "owner=sam"),
        ("array", ["owner=sam"]),
        ("number", 42),
        ("boolean", true),
        ("null", NSNull())
    ]

    private func makeIntentServices() throws -> IntentServices {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = Project(
            name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return IntentServices(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
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

    // MARK: - JSON CreateTaskIntent

    @Test func createTaskIntentRejectsEveryNonObjectMetadataShapeWithoutMutation() async throws {
        let services = try makeIntentServices()
        let validInput = try jsonInput([
            "name": "Task without metadata",
            "type": "feature",
            "projectId": services.projectModel.id.uuidString
        ])
        let validResult = await CreateTaskIntent.execute(
            input: validInput,
            taskService: services.task,
            projectService: services.project
        )
        let validTaskID = try #require(try parseJSON(validResult)["taskId"] as? String)
        let validTaskUUID = try #require(UUID(uuidString: validTaskID))

        for entry in nonObjectValues {
            let input = try jsonInput([
                "name": "Task with invalid metadata \(entry.label)",
                "type": "feature",
                "projectId": services.projectModel.id.uuidString,
                "metadata": entry.value
            ])

            let result = await CreateTaskIntent.execute(
                input: input,
                taskService: services.task,
                projectService: services.project
            )

            let parsed = try parseJSON(result)
            #expect(parsed["error"] as? String == "INVALID_INPUT")
            #expect(parsed["hint"] as? String == "metadata must be an object")
        }

        #expect(try services.context.fetch(FetchDescriptor<TransitTask>()).map(\.id) == [validTaskUUID])
    }

#if os(macOS)
    // MARK: - MCP create_task

    @Test func mcpCreateTaskRejectsEveryNonObjectMetadataShapeWithoutMutation() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let validResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task without metadata",
                "type": "feature",
                "projectId": project.id.uuidString
            ]
        ))
        let validTaskID = try #require(try MCPTestHelpers.decodeResult(validResponse)["taskId"] as? String)
        let validTaskUUID = try #require(UUID(uuidString: validTaskID))

        for entry in nonObjectValues {
            let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "create_task",
                arguments: [
                    "name": "Task with invalid metadata \(entry.label)",
                    "type": "feature",
                    "projectId": project.id.uuidString,
                    "metadata": entry.value
                ]
            ))

            #expect(try MCPTestHelpers.isError(response))
            #expect(try MCPTestHelpers.errorText(response) == "metadata must be an object")
        }

        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).map(\.id) == [validTaskUUID])
    }

    @Test func mcpCreateTaskSchemaRequiresMetadataObject() throws {
        let metadataSchema = try #require(
            MCPToolDefinitions.createTask.inputSchema.properties?["metadata"]
        )
        #expect(metadataSchema.type == "object")
    }
#endif
}
