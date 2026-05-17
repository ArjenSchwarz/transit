import Foundation
import Testing
@testable import Transit

/// Invariant: the create_task schema and App Intent description must advertise
/// that at least one of `projectId` / `project` is required, matching runtime behaviour.
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

    /// Guards against drift between `inputParameterDescription` (which the tests
    /// inspect) and the `@Parameter(description:)` literal that App Intents
    /// actually uses. The macro requires a string literal, so both copies must
    /// be updated together — this test reads the source file and asserts the
    /// `@Parameter(description:)` block contains the same constraint phrase.
    @Test func intentParameterDescriptionMatchesStaticLiteral() throws {
        let sourcePath = Self.createTaskIntentSourcePath()
        let source = try String(contentsOf: sourcePath, encoding: .utf8)

        // Locate the @Parameter(...) block following the `title: "Input JSON"` marker
        // to scope the assertion to the input parameter (not unrelated text).
        guard let parameterRange = source.range(of: "title: \"Input JSON\"") else {
            Issue.record("Could not locate @Parameter(title: \"Input JSON\") in source")
            return
        }
        let parameterTail = source[parameterRange.upperBound...]
        guard let closing = parameterTail.range(of: "var input: String") else {
            Issue.record("Could not locate end of @Parameter block in source")
            return
        }
        let parameterBlock = String(parameterTail[..<closing.lowerBound])

        #expect(
            parameterBlock.lowercased().contains("at least one"),
            "@Parameter(description:) literal must state that at least one project identifier is required"
        )
        #expect(
            !parameterBlock.contains("Optional: \"projectId\""),
            "@Parameter(description:) literal still marks projectId as optional"
        )
    }

    private static func createTaskIntentSourcePath() -> URL {
        // #filePath points at this test file:
        //   .../Transit/TransitTests/CreateTaskProjectRequiredSchemaTests.swift
        // The intent lives at:
        //   .../Transit/Transit/Intents/CreateTaskIntent.swift
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()        // TransitTests/
            .deletingLastPathComponent()        // Transit/ (project root)
            .appendingPathComponent("Transit")
            .appendingPathComponent("Intents")
            .appendingPathComponent("CreateTaskIntent.swift")
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
