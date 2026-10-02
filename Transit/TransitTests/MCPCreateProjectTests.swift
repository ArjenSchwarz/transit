#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPCreateProjectTests {
    private struct FetchFailure: Error {}

    private struct FailingFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    @Test func schemaIsDiscoverable() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = await env.handler.handle(MCPTestHelpers.request(method: "tools/list"))
        let data = try JSONEncoder().encode(try #require(response))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let tool = try #require(tools.first { $0["name"] as? String == "create_project" })
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        #expect(Set(try #require(schema["required"] as? [String])) == ["name", "colorHex"])
        let properties = try #require(schema["properties"] as? [String: [String: Any]])
        for key in ["name", "colorHex", "description", "gitRepo"] {
            #expect(properties[key]?["type"] as? String == "string")
        }
    }

    @Test func createsProjectWithMetadataAndUsableIdentifier() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let description = "Line one\nLine two \\n"
        let repo = "git@example.com:team/project.git"
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: [
                "name": "  New Project\n", "colorHex": "#aB12ef", "description": description, "gitRepo": repo
            ]
        ))
        #expect(try !MCPTestHelpers.isError(response))
        let result = try MCPTestHelpers.decodeResult(response)
        let projectId = try #require(result["projectId"] as? String)
        #expect(UUID(uuidString: projectId) != nil)
        #expect(result["name"] as? String == "New Project")
        #expect(result["description"] as? String == description)
        #expect(result["gitRepo"] as? String == repo)
        #expect(result["colorHex"] as? String == "#aB12ef")
        #expect(result["activeTaskCount"] as? Int == 0)
        let persisted = try #require(env.context.fetch(FetchDescriptor<Project>()).first)
        #expect(persisted.id.uuidString == projectId)
        #expect(persisted.projectDescription == description)
        let listed = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "get_projects", arguments: [:]))
        let projects = try MCPTestHelpers.decodeArrayResult(listed)
        #expect(projects.count == 1)
        #expect(NSDictionary(dictionary: try #require(projects.first)) == NSDictionary(dictionary: result))
        let taskResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task", arguments: ["name": "First task", "type": "feature", "projectId": projectId]
        ))
        #expect(try !MCPTestHelpers.isError(taskResponse))
        let task = try #require(env.context.fetch(FetchDescriptor<TransitTask>()).first)
        #expect(task.project?.id == persisted.id)
    }

    @Test func optionalFieldsCanBeOmittedOrEmpty() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: ["name": "Minimal", "colorHex": "000000"]
        ))
        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["description"] as? String == "")
        #expect(result["gitRepo"] == nil)
        let empty = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project",
            arguments: ["name": "Empty", "colorHex": "#FFFFFF", "description": "", "gitRepo": ""]
        ))
        #expect(try MCPTestHelpers.decodeResult(empty)["gitRepo"] as? String == "")
    }

    @Test func rejectsMissingAndMalformedFieldsWithoutInsertion() async throws {
        let invalidValues: [Any] = [42, true, NSNull(), [], ["key": "value"]]
        for key in ["name", "colorHex", "description", "gitRepo"] {
            for value in invalidValues {
                let env = try MCPTestHelpers.makeEnv()
                var args: [String: Any] = ["name": "New", "colorHex": "#123ABC"]
                args[key] = value
                let response = await env.handler.handle(
                    MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: args)
                )
                #expect(try MCPTestHelpers.isError(response))
                #expect(try MCPTestHelpers.errorText(response) == "\(key) must be a string")
                #expect(try env.context.fetch(FetchDescriptor<Project>()).isEmpty)
            }
        }
        for key in ["name", "colorHex"] {
            let env = try MCPTestHelpers.makeEnv()
            var args: [String: Any] = ["name": "New", "colorHex": "#123ABC"]
            args.removeValue(forKey: key)
            let response = await env.handler.handle(
                MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: args)
            )
            #expect(try MCPTestHelpers.errorText(response) == "Missing required argument: \(key)")
            #expect(try env.context.fetch(FetchDescriptor<Project>()).isEmpty)
        }
    }

    @Test(arguments: ["", " \n\t", "#ABC", "#12345G", "#12345678", "#123456\n", "#123456\r\n", "#１２３４５６", " #123456"])
    func rejectsInvalidColors(color: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: ["name": "New", "colorHex": color]
        ))
        #expect(try MCPTestHelpers.isError(response))
        #expect(try env.context.fetch(FetchDescriptor<Project>()).isEmpty)
    }

    @Test(arguments: ["", " \n\t"])
    func rejectsBlankNames(name: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: ["name": name, "colorHex": "#123456"]
        ))
        #expect(try MCPTestHelpers.isError(response))
        #expect(try env.context.fetch(FetchDescriptor<Project>()).isEmpty)
    }

    @Test func rejectsDuplicateNameAndPreservesExistingProject() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let existing = try env.projectService.createProject(
            name: "Existing", description: "Original", gitRepo: nil, colorHex: "#123456"
        )
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: ["name": "  eXISTING\n", "colorHex": "#ABCDEF"]
        ))
        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("already exists"))
        let projects = try env.context.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 1)
        #expect(projects.first?.id == existing.id)
        #expect(existing.projectDescription == "Original")
    }

    @Test func failedUniquenessReadDoesNotCreateProject() async throws {
        let env = try MCPTestHelpers.makeEnv(projectFetcher: FailingFetcher())
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: ["name": "New", "colorHex": "#ABCDEF"]
        ))
        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("Failed to create project"))
        #expect(try env.context.fetch(FetchDescriptor<Project>()).isEmpty)
    }
}
#endif
