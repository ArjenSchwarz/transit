#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

/// App-test-owned in-memory providers; no production store, listener or client activation.
@MainActor enum MCPModernResultFixture {
    static let meta: [String: Any] = ["protocolVersion": "2026-07-28", "clientCapabilities": [:] as [String: Any]]

    static func makeEnvWithReads() throws -> MCPTestEnv {
        let env = try MCPTestHelpers.makeEnv()
        let snapshots = env.handler.taskQuerySnapshots
        let source = MCPReadCaptureBuilder(container: env.context.container, fence: .actorOnlyTestFixture)
        let service = MCPReadService(source: source,
            monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil), snapshots: snapshots)
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings,
            taskQuerySnapshots: snapshots, writeCoordinator: env.writeCoordinator, readService: service,
            readCoordinator: env.handler.readCoordinator)
        return MCPTestEnv(handler: handler, taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, mcpSettings: env.mcpSettings, context: env.context,
            writeCoordinator: env.writeCoordinator, sidecarDirectory: env.sidecarDirectory)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func validArguments(tool: String, env: MCPTestEnv, project: Project,
                               task: TransitTask, milestone: Milestone) throws -> [String: Any] {
        var args: [String: Any] = [:]
        switch tool {
        case "create_project": args = ["name": "New Project", "colorHex": "#334455"]
        case "create_task": args = ["name": "New Task", "type": "feature", "projectId": project.id.uuidString]
        case "create_milestone": args = ["name": "New Milestone", "projectId": project.id.uuidString]
        case "update_task": args = ["taskId": task.id.uuidString, "name": "Updated Task"]
        case "update_task_status": args = ["taskId": task.id.uuidString, "status": "in-progress"]
        case "add_comment": args = ["taskId": task.id.uuidString, "content": "Saved Comment", "authorName": "Fixture"]
        case "update_milestone": args = ["milestoneId": milestone.id.uuidString, "name": "Updated Milestone"]
        case "delete_milestone": args = ["milestoneId": milestone.id.uuidString]
        case "query_tasks": args = ["detailLevel": "full", "includeComments": false, "readPolicy": "cached"]
        case "query_milestones", "get_projects": args = ["readPolicy": "cached"]
        case "query_project_summaries": args = [
            "start": "2026-01-01T00:00:00Z", "end": "2026-12-31T00:00:00Z",
            "limit": 100, "readPolicy": "cached"
        ]
        default: break
        }
        if MCPWriteCommand.protectedTools.contains(tool) { args["idempotencyKey"] = "all-tools-" + tool }
        if ["update_task", "update_task_status"].contains(tool) {
            args["expectedRevision"] = try MCPTestHelpers.readRevision(task, in: env.context)
        }
        if ["update_milestone", "delete_milestone"].contains(tool) {
            args["expectedRevision"] = try MCPTestHelpers.readRevision(milestone)
        }
        return args
    }

    static func body(method: String, id: Any = 1, parameters: [String: Any] = [:]) throws -> String {
        var params = parameters
        params["_meta"] = meta
        let bytes = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ], options: [.sortedKeys])
        return try #require(String(data: bytes, encoding: .utf8))
    }

    static func respond(_ env: MCPTestEnv, method: String, id: Any = 1,
                        parameters: [String: Any] = [:], headers: [HTTPField] = [],
                        origin: String? = nil) async throws -> MCPHTTPTestResponse {
        var fields = [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: method)]
        if let name = parameters["name"] as? String {
            fields.append(HTTPField(name: HTTPField.Name("Mcp-Name")!, value: name))
        }
        fields.append(contentsOf: headers)
        return try await MCPTestHelpers.respond(handler: env.handler, origin: origin,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: "2026-07-28", orderedHeaders: fields,
            body: body(method: method, id: id, parameters: parameters), loggerLabel: "t2383-modern-result-fixture")
    }

    static func call(_ env: MCPTestEnv, tool: String, arguments: [String: Any],
                     id: Any = 1) async throws -> MCPHTTPTestResponse {
        try await respond(env, method: "tools/call", id: id, parameters: ["name": tool, "arguments": arguments])
    }

    static func text(_ response: MCPHTTPTestResponse) throws -> String {
        let root = try MCPJSONDocument.parse(response.body).value
        let result = try #require(MCPResultEncoderFixtures.field("result", in: root))
        #expect(MCPResultEncoderFixtures.field("resultType", in: result) == .string("complete"))
        return try MCPResultEncoderFixtures.originalText(result)
    }

    static func assertSource(_ response: MCPHTTPTestResponse, id: JSONRPCId) throws -> MCPJSONValue {
        let result = try MCPResultEncoderFixtures.result(response.body, id: id)
        let original = try MCPResultEncoderFixtures.originalText(result)
        let structured = try MCPResultEncoderFixtures.structured(result)
        let source = try #require(MCPResultEncoderFixtures.field("source", in: structured))
        switch MCPResultEncoderFixtures.field("kind", in: source) {
        case .string("json"):
            #expect(try MCPResultEncoderFixtures.rawFragment(response.body,
                path: ["result", "structuredContent", "source", "payload"]) == Data(original.utf8))
        case .string("text"):
            #expect(MCPResultEncoderFixtures.field("payload", in: source) == .string(original))
        case .string("unreadable"):
            #expect(MCPResultEncoderFixtures.field("payload", in: source) == nil)
            let presentation = MCPResultEncoderFixtures.field("presentation", in: structured)
            #expect(MCPResultEncoderFixtures.field("evidence", in: presentation) == .string("unestablished"))
        default: Issue.record("Missing declared source kind")
        }
        return result
    }
}
#endif
