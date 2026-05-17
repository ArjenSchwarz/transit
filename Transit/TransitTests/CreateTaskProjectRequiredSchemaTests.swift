import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1170 — Create task APIs mark required project as optional.
///
/// Bug: `CreateTaskIntent` documents `projectId` / `project` as optional, and MCP
/// `create_task` only lists `name` and `type` as required. The implementation then
/// rejects calls that omit both with `Either projectId or project name is required`.
/// This makes valid-looking App Intent / MCP calls fail at runtime and gives tool
/// clients the wrong schema. The fix aligns the advertised schema/description with
/// the runtime requirement (at least one of projectId / project must be supplied),
/// mirroring how `create_milestone` already documents this.
@MainActor @Suite(.serialized)
struct CreateTaskProjectRequiredSchemaTests {

    // MARK: - CreateTaskIntent Parameter Documentation

    /// The intent's `input` parameter description must not advertise project as a
    /// purely optional field, since the implementation rejects calls that omit
    /// both `projectId` and `project`.
    @Test func createTaskIntentDescriptionDoesNotMarkProjectAsOptional() async throws {
        let description = CreateTaskIntent.inputParameterDescription

        // Negative assertion: the previous text bundled projectId/project under
        // "Optional: ...". After the fix the description must clearly indicate
        // that at least one project identifier is required.
        #expect(
            !description.contains("Optional: \"projectId\""),
            "CreateTaskIntent description still marks projectId as optional, contradicting runtime behaviour"
        )
        #expect(
            description.lowercased().contains("at least one"),
            "CreateTaskIntent description should state that at least one project identifier is required"
        )
    }

    // MARK: - MCP create_task Tool Schema

    #if os(macOS)
    /// The MCP `create_task` tool description must communicate that a project is
    /// required, since the handler returns an error if both `projectId` and
    /// `project` are missing. This mirrors `create_milestone`, which already
    /// documents the same constraint in its tool description.
    @Test func mcpCreateTaskDescriptionStatesProjectIsRequired() {
        let description = MCPToolDefinitions.createTask.description
        #expect(
            description.lowercased().contains("at least one")
                && description.contains("project"),
            "MCP create_task description should state that at least one of project / projectId is required"
        )
    }

    /// The MCP `create_task` property descriptions for `projectId` and `project`
    /// must not advertise them as plainly optional, since omitting both is an error.
    @Test func mcpCreateTaskPropertyDescriptionsReflectRequirement() throws {
        let schema = MCPToolDefinitions.createTask.inputSchema
        let properties = try #require(schema.properties)
        let projectIdProperty = try #require(properties["projectId"])
        let projectProperty = try #require(properties["project"])

        let projectIdDescription = try #require(projectIdProperty.description)
        let projectDescription = try #require(projectProperty.description)

        #expect(
            !projectIdDescription.lowercased().contains("optional"),
            "create_task projectId description should not be marked optional in isolation"
        )
        #expect(
            !projectDescription.lowercased().contains("optional"),
            "create_task project description should not be marked optional in isolation"
        )
    }
    #endif
}
