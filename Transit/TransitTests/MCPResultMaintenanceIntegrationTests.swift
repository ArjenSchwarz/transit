#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPResultMaintenanceIntegrationTests {
    private enum Fault: Error { case inner, outer, preparation }
    private nonisolated final class Counts: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func record() { lock.lock(); defer { lock.unlock() }; value += 1 }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test func actualInnerEncodingFailureAfterSavedReassignmentUsesNoKeyReconciliation() async throws {
        let env = try await duplicateEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let calls = Counts()
        let handler = MCPToolHandler(taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, settings: env.mcpSettings,
            writeCoordinator: env.writeCoordinator, maintenanceReassignmentEncoder: { _ in
                calls.record()
                throw Fault.inner
            })
        let faultEnv = MCPTestEnv(handler: handler, taskService: env.taskService, projectService: env.projectService,
            commentService: env.commentService, milestoneService: env.milestoneService,
            maintenanceService: env.maintenanceService, mcpSettings: env.mcpSettings, context: env.context,
            writeCoordinator: env.writeCoordinator, sidecarDirectory: env.sidecarDirectory)
        let response = try await MCPModernResultFixture.call(faultEnv, tool: "reassign_duplicate_display_ids",
                                                             arguments: [:], id: "inner-fault")
        #expect(calls.count == 1)
        try assertSavedReassignment(env)
        let result = try MCPModernResultFixture.assertSource(response, id: .string("inner-fault"))
        try assertMaintenanceRecovery(result)
    }

    @Test func actualSavedMaintenanceThenFinalEnvelopeFailureSelectsReadyBytesOnce() async throws {
        let env = try await duplicateEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let handler = env.handler
        let calls = Counts()
        let fixed = context()
        let fallback = try fallbackSource()
        let id = JSONRPCId.string("outer-fault")
        let ready = try MCPResultProviderSelection.prepare(id: id, source: fallback, context: fixed, metadata: nil)
        let selected = try await MCPResultProviderSelection.mutation(id: id, context: fixed,
            metadata: nil, fallbackSource: fallback, encodeOutcome: { _, _, _ in
                calls.record(); throw Fault.outer
            }, dispatch: { try await Self.actualOutcome(handler, context: fixed) })
        guard case .reconciliation(let bytes) = selected else {
            Issue.record("Expected already prepared post-effect response"); throw Fault.outer
        }
        #expect(bytes == ready)
        #expect(calls.count == 1)
        try assertSavedReassignment(env)
        try assertMaintenanceRecovery(MCPResultEncoderFixtures.result(bytes, id: id))
    }

    @Test func actualMaintenanceDeliverySuppressionRetainsSavedEffects() async throws {
        let env = try await duplicateEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let handler = env.handler
        let fixed = context()
        let completed = Counts()
        let selected = try await MCPResultProviderSelection.mutation(id: .string("delivery-fault"), context: fixed,
            metadata: nil, fallbackSource: fallbackSource(), shouldDeliver: { completed.count == 0 }, dispatch: {
                let outcome = try await Self.actualOutcome(handler, context: fixed)
                completed.record()
                return outcome
            })
        if case .suppressed = selected {} else { Issue.record("Expected delivery suppression") }
        #expect(completed.count == 1)
        try assertSavedReassignment(env)
    }

    @Test func preparationFailureNeverInvokesActualMaintenanceEffects() async throws {
        let env = try await duplicateEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let handler = env.handler
        let fixed = context()
        let calls = Counts()
        do {
            _ = try await MCPResultProviderSelection.mutation(id: .string("prep-fault"), context: fixed,
                metadata: nil, fallbackSource: fallbackSource(),
                prepareFallback: { _, _, _, _ in throw Fault.preparation },
                dispatch: { calls.record(); return try await Self.actualOutcome(handler, context: fixed) })
            Issue.record("Expected original preparation failure")
        } catch Fault.preparation {}
        #expect(calls.count == 0)
        let fresh = ModelContext(env.context.container)
        fresh.autosaveEnabled = false
        #expect(try fresh.fetch(FetchDescriptor<TransitTask>()).compactMap(\.permanentDisplayId) == [99, 99])
    }

    private func duplicateEnv() async throws -> MCPTestEnv {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        let project = try env.projectService.createProject(name: "Maintenance Fixture", description: "",
                                                           gitRepo: nil, colorHex: "#112233")
        let first = try await env.taskService.createTask(name: "First", description: nil,
                                                        type: .feature, project: project)
        let second = try await env.taskService.createTask(name: "Second", description: nil,
                                                        type: .feature, project: project)
        first.permanentDisplayId = 99
        second.permanentDisplayId = 99
        try env.context.save()
        return env
    }

    private func context() -> MCPResultContext {
        MCPResultContext(tool: "reassign_duplicate_display_ids", semanticFailure: nil,
            mutationRecovery: .unprotectedMaintenance(tool: "reassign_duplicate_display_ids"), entityPositions: [])
    }

    private func fallbackSource() throws -> MCPResultSource {
        try MCPResultAdapter.source(text: #"{"error":{"code":"OUTCOME_UNKNOWN"}}"#, isError: true,
                                    origin: .generatedJSON, evidence: .unestablished)
    }

    private static func actualOutcome(_ handler: MCPToolHandler,
                                      context: MCPResultContext) async throws -> MCPResultProviderOutcome {
        let request = MCPTestHelpers.toolCallRequest(tool: "reassign_duplicate_display_ids", arguments: [:])
        let response = try #require(await handler.handle(request))
        let tool = try #require(response.result?.value as? MCPToolResult)
        let text = try #require(tool.content.first?.text)
        let source = try MCPResultAdapter.source(text: text, isError: tool.isError,
                                                 origin: .generatedJSON, evidence: .established)
        return MCPResultProviderOutcome(source: source, context: context)
    }

    private func assertSavedReassignment(_ env: MCPTestEnv) throws {
        let fresh = ModelContext(env.context.container)
        fresh.autosaveEnabled = false
        let tasks = try fresh.fetch(FetchDescriptor<TransitTask>())
        let values = tasks.compactMap(\.permanentDisplayId)
        #expect(values.count == 2)
        #expect(Set(values).count == 2)
        #expect(values.contains(99))
        #expect(try fresh.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    private func assertMaintenanceRecovery(_ result: MCPJSONValue) throws {
        let structured = try MCPResultEncoderFixtures.structured(result)
        let presentation = MCPResultEncoderFixtures.field("presentation", in: structured)
        #expect(MCPResultEncoderFixtures.field("evidence", in: presentation) == .string("unestablished"))
        let recovery = MCPResultEncoderFixtures.field("recovery", in: presentation)
        #expect(MCPResultEncoderFixtures.field("direction", in: recovery) == .string("reconcile_maintenance"))
        #expect(MCPResultEncoderFixtures.field("tool", in: recovery) == .string("reassign_duplicate_display_ids"))
        #expect(MCPResultEncoderFixtures.field("idempotencyKey", in: recovery) == nil)
    }
}
#endif
