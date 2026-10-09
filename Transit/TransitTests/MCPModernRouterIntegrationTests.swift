#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPModernRouterIntegrationTests {
    @Test func discoverAndSortedToolListPublishCompleteOutputSchemas() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        env.mcpSettings.maintenanceToolsEnabled = true
        for method in ["server/discover", "tools/list"] {
            let response = try await MCPModernResultFixture.respond(env, method: method)
            #expect(response.status == .ok)
            let object = try #require(response.json as? [String: Any])
            let result = try #require(object["result"] as? [String: Any])
            #expect(result["resultType"] as? String == "complete")
            #expect(result["ttlMs"] as? Int == 0)
            #expect(result["cacheScope"] as? String == "public")
            if method == "server/discover" {
                let metadata = try #require(result["_meta"] as? [String: Any])
                let identity = try #require(metadata["io.modelcontextprotocol/serverInfo"] as? [String: Any])
                #expect(identity["name"] as? String == "transit-debug")
            }
            if method == "tools/list" {
                let tools = try #require(result["tools"] as? [[String: Any]])
                let names = tools.compactMap { $0["name"] as? String }
                #expect(names == names.sorted())
                #expect(Set(names) == Set(MCPToolDefinitions.tools(includingMaintenance: true).map(\.name)))
                for tool in tools {
                    let schema = try #require(tool["outputSchema"] as? [String: Any])
                    #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
                    #expect(schema["$defs"] is [String: Any])
                }
            }
        }
    }

    @Test func everyEnabledCurrentToolReturnsDeclaredCompleteSource() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        env.mcpSettings.maintenanceToolsEnabled = true
        let project = try env.projectService.createProject(name: "Existing", description: "", gitRepo: nil,
                                                           colorHex: "#112233")
        let task = try await env.taskService.createTask(name: "Existing Task", description: "Description",
                                                        type: .feature, project: project)
        let milestone = try await env.milestoneService.createMilestone(name: "Existing Milestone",
                                                                       description: nil, project: project)
        for definition in MCPToolDefinitions.tools(includingMaintenance: true) {
            let args = try MCPModernResultFixture.validArguments(tool: definition.name, env: env,
                                                                project: project, task: task, milestone: milestone)
            let response = try await MCPModernResultFixture.call(env, tool: definition.name, arguments: args)
            #expect(response.status == .ok)
            let result = try MCPModernResultFixture.assertSource(response, id: .integer(1))
            #expect(MCPResultEncoderFixtures.field("isError", in: result) != .boolean(true))
            let covered = ["query_tasks", "query_milestones", "get_projects", "query_project_summaries"]
            if covered.contains(definition.name) {
                #expect(MCPResultEncoderFixtures.field("_meta", in: result) != nil)
            }
        }
    }

    private actor ReadHold {
        private var entered = false
        private var entryWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?
        func block() async {
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        func waitForEntry() async {
            if entered { return }
            await withCheckedContinuation { entryWaiter = $0 }
        }
        func release() { releaseWaiter?.resume(); releaseWaiter = nil }
    }

    @Test func coveredInvalidArgumentsRespectSaturatedAdmissionBeforeDomainValidation() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let domain = env.handler.taskQuerySnapshots.domain
        let coordinator = MCPReadCoordinator(domain: domain, maxOperations: 1)
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings,
            taskQuerySnapshots: env.handler.taskQuerySnapshots, writeCoordinator: env.writeCoordinator,
            readService: env.handler.readService, readCoordinator: coordinator)
        let hold = ReadHold()
        let runner = Task.detached {
            await coordinator.execute(timeout: Data("held-timeout".utf8), busy: Data("held-busy".utf8)) { _ in
                await hold.block()
                return PreparedReadResult(encodedResponse: Data("held-done".utf8), publications: [],
                    publicationErrors: PreencodedPublicationErrors(busy: Data(), expired: Data(), capacity: Data()))
            }
        }
        await hold.waitForEntry()
        do {
            let body = try MCPModernResultFixture.body(method: "tools/call",
                parameters: ["name": "query_tasks", "arguments": "invalid-object-shape"])
            let response = try await MCPModernResultFixture.transport(
                handler: handler, contentType: "application/json",
                accept: "application/json, text/event-stream", protocolVersion: "2026-07-28", orderedHeaders: [
                    HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call"),
                    HTTPField(name: HTTPField.Name("Mcp-Name")!, value: "query_tasks")
                ], body: body, loggerLabel: "t2383-covered-admission")
            let text = try MCPModernResultFixture.text(response)
            #expect(text.contains("READ_BUSY"))
            _ = try MCPModernResultFixture.assertSource(response, id: .integer(1))
        } catch {
            await hold.release()
            _ = await runner.value
            throw error
        }
        await hold.release()
        _ = await runner.value
    }

    private nonisolated final class MainActorHold: @unchecked Sendable {
        private let entered = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var blocked = false
        private var explicitlyReleased = false
        @MainActor func block() {
            lock.lock(); blocked = true; lock.unlock()
            entered.signal()
            let result = released.wait(timeout: .now() + .seconds(2))
            lock.lock(); explicitlyReleased = result == .success; lock.unlock()
            lock.lock(); blocked = false; lock.unlock()
        }
        func waitForEntry() -> Bool { entered.wait(timeout: .now() + .seconds(2)) == .success }
        func release() { released.signal() }
        var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return blocked }
        var completedByRelease: Bool { lock.lock(); defer { lock.unlock() }; return explicitlyReleased }
    }

    @Test func immutableUnavailableToolClassificationDoesNotWaitForMainActor() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let handler = env.handler
        let body = try MCPModernResultFixture.body(method: "tools/call",
            parameters: ["name": "unavailable_tool", "arguments": [:] as [String: Any]])
        let hold = MainActorHold()
        let scenario = Task.detached {
            let blocker = Task { @MainActor in hold.block() }
            guard hold.waitForEntry() else {
                hold.release()
                await blocker.value
                throw FixtureFailure.barrier
            }
            do {
                let response = try await MCPModernResultFixture.transport(
                    handler: handler, contentType: "application/json",
                    accept: "application/json, text/event-stream", protocolVersion: "2026-07-28", orderedHeaders: [
                        HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call"),
                        HTTPField(name: HTTPField.Name("Mcp-Name")!, value: "unavailable_tool")
                    ], body: body, loggerLabel: "t2383-immutable-classification")
                let beforeRelease = hold.isBlocked
                hold.release()
                await blocker.value
                return (response, beforeRelease, hold.completedByRelease)
            } catch {
                hold.release()
                await blocker.value
                throw error
            }
        }
        let (response, beforeRelease, completedByRelease) = try await scenario.value
        #expect(completedByRelease)
        #expect(beforeRelease)
        #expect(response.status == .badRequest)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    private enum FixtureFailure: Error { case barrier }

    @Test func originAndDuplicateRequiredHeadersRejectBeforeAcceptance() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let parameters: [String: Any] = ["name": "create_project", "arguments": [
            "name": "Blocked", "colorHex": "#112233", "idempotencyKey": "blocked-key"
        ]]
        let origin = try await MCPModernResultFixture.respond(env, method: "tools/call",
            parameters: parameters, origin: "https://untrusted.invalid")
        #expect(origin.status == .forbidden)
        let duplicated = try await MCPModernResultFixture.respond(env, method: "tools/call",
            parameters: parameters, headers: [HTTPField(name: HTTPField.Name("Mcp-Name")!, value: "create_project")])
        #expect(duplicated.status == .badRequest)
        #expect(try env.context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func notificationMutationRejectsWithoutAcceptanceOrFabricatedID() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let body = ##"""
            {"jsonrpc":"2.0","method":"tools/call","params":{"name":"create_project",
            "arguments":{"name":"Blocked","colorHex":"#112233","idempotencyKey":"notify-key"},
            "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",
            "io.modelcontextprotocol/clientCapabilities":{}}}}
            """##
        let response = try await MCPModernResultFixture.transport(handler: env.handler,
            contentType: "application/json", accept: "application/json, text/event-stream",
            protocolVersion: "2026-07-28", orderedHeaders: [
                HTTPField(name: HTTPField.Name("Mcp-Method")!, value: "tools/call"),
                HTTPField(name: HTTPField.Name("Mcp-Name")!, value: "create_project")
            ], body: body, loggerLabel: "t2383-notification")
        #expect(response.status == .badRequest)
        if let object = response.json as? [String: Any] { #expect(object["id"] == nil) }
        #expect(try env.context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }
}
#endif
