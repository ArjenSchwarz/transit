#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Consumers of real protected providers; coordinator policy remains owned by T2384.
@MainActor @Suite(.serialized)
struct MCPResultProviderIntegrationTests {
    @Test func savedReceiptReplayAfterEditAndDeletionUsesOriginalTextAndNewRPCID() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let args: [String: Any] = ["name": "  Original Project\n", "colorHex": "#112233",
                                   "description": "\nSaved description\n", "idempotencyKey": "replay-project-key"]
        let initial = try await MCPModernResultFixture.call(env, tool: "create_project", arguments: args, id: "first")
        let original = try MCPModernResultFixture.text(initial)
        let initialResult = try MCPModernResultFixture.assertSource(initial, id: .string("first"))
        let receipt = try #require(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        let stored = try #require(receipt.resultJSON)
        #expect(original == stored)
        let request = receipt.requestJSON
        let expiry = receipt.expiresAt
        let completed = receipt.completedAt
        let receiptID = receipt.id
        let errorFlag = receipt.resultIsError
        let project = try #require(try env.context.fetch(FetchDescriptor<Project>()).first)
        project.name = "Edited after receipt"
        try env.context.save()
        let edited = try await MCPModernResultFixture.call(env, tool: "create_project", arguments: args, id: "edited")
        #expect(try MCPModernResultFixture.text(edited) == stored)
        let editedResult = try MCPModernResultFixture.assertSource(edited, id: .string("edited"))
        env.context.delete(project)
        try env.context.save()
        let deleted = try await MCPModernResultFixture.call(env, tool: "create_project", arguments: args, id: "deleted")
        #expect(try MCPModernResultFixture.text(deleted) == stored)
        let deletedResult = try MCPModernResultFixture.assertSource(deleted, id: .string("deleted"))
        for result in [initialResult, editedResult, deletedResult] {
            #expect(MCPResultEncoderFixtures.field("isError", in: result)
                == (errorFlag == true ? .boolean(true) : nil))
        }
        #expect(try env.context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 1)
        #expect(receipt.id == receiptID)
        #expect(receipt.resultJSON == stored)
        #expect(receipt.resultIsError == errorFlag)
        #expect(receipt.requestJSON == request)
        #expect(receipt.expiresAt == expiry)
        #expect(receipt.completedAt == completed)
    }

    @Test func actualProtectedUpdateTrimClearAndCommentRevisionRemainSavedEvidence() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let project = try env.projectService.createProject(
            name: "Fixture", description: "", gitRepo: nil, colorHex: "#112233")
        let create = try await MCPModernResultFixture.call(env, tool: "create_task", arguments: [
            "name": "  First Task\n", "description": "\nCreate description\n", "type": "feature",
            "projectId": project.id.uuidString, "idempotencyKey": "normalize-create"
        ])
        _ = try MCPModernResultFixture.assertSource(create, id: .integer(1))
        let task = try #require(try env.context.fetch(FetchDescriptor<TransitTask>()).first)
        let update = try await MCPModernResultFixture.call(env, tool: "update_task", arguments: [
            "taskId": task.id.uuidString, "name": "  Saved Task\n", "description": "\n  Body\nwith newline  \n",
            "expectedRevision": try MCPTestHelpers.readRevision(task, in: env.context),
            "idempotencyKey": "normalize-update"
        ], id: "update")
        let updateRecord = try savedRecord(update)
        #expect(task.name == "Saved Task")
        #expect(task.taskDescription == "Body\nwith newline")
        #expect(updateRecord["name"] as? String == task.name)
        #expect(updateRecord["description"] as? String == task.taskDescription)
        #expect(try updateRecord["revision"] as? String == MCPTestHelpers.readRevision(task, in: env.context))
        _ = try MCPModernResultFixture.assertSource(update, id: .string("update"))
        let beforeComment = try MCPTestHelpers.readRevision(task, in: env.context)
        let comment = try await MCPModernResultFixture.call(env, tool: "add_comment", arguments: [
            "taskId": task.id.uuidString, "content": "  Comment\nsecond line \n", "authorName": " Agent \n",
            "idempotencyKey": "normalize-comment"
        ], id: "comment")
        let commentRecord = try savedRecord(comment)
        #expect(commentRecord["content"] as? String == "Comment\nsecond line")
        #expect(commentRecord["authorName"] as? String == "Agent")
        _ = try MCPModernResultFixture.assertSource(comment, id: .string("comment"))
        #expect(try MCPTestHelpers.readRevision(task, in: env.context) != beforeComment)
        let clear = try await MCPModernResultFixture.call(env, tool: "update_task", arguments: [
            "taskId": task.id.uuidString, "description": " \n\t ",
            "expectedRevision": try MCPTestHelpers.readRevision(task, in: env.context),
            "idempotencyKey": "normalize-clear"
        ], id: "clear")
        let cleared = try savedRecord(clear)
        #expect(task.taskDescription == nil)
        #expect(cleared.keys.contains("description"))
        #expect(cleared["description"] is NSNull)
        #expect(try cleared["revision"] as? String == MCPTestHelpers.readRevision(task, in: env.context))
        _ = try MCPModernResultFixture.assertSource(clear, id: .string("clear"))
        try await assertReadParity(env, task: task, project: project,
                                   savedRevision: #require(cleared["revision"] as? String))
    }

    @Test func dirtyUIContextIsUntouchedBySavedEvidenceAdapter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: [
            "name": "Saved", "colorHex": "#112233", "idempotencyKey": "dirty-source-key"
        ]))
        let object = try #require(response)
        _ = try JSONEncoder().encode(object)
        let receipt = try #require(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        let saved = try #require(receipt.resultJSON)
        let expiry = receipt.expiresAt
        let project = try #require(try env.context.fetch(FetchDescriptor<Project>()).first)
        project.name = "Unsaved UI edit"
        #expect(env.context.hasChanges)
        let source = try MCPResultAdapter.source(text: saved, isError: receipt.resultIsError == true ? true : nil,
                                                 origin: .retainedJSON, evidence: .established)
        let fixed = MCPResultContext(tool: "create_project", semanticFailure: nil,
            mutationRecovery: .protectedWrite(.init(tool: "create_project", idempotencyKey: "dirty-source-key")),
            entityPositions: [.init(entityType: .project, sourcePath: "/record")])
        let presentation = try MCPResultAdapter.present(source, context: fixed)
        let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                                                 id: .string("dirty-evidence"), metadata: nil)
        let modern = try MCPResultEncoderFixtures.result(bytes, id: .string("dirty-evidence"))
        #expect(try MCPResultEncoderFixtures.originalText(modern) == saved)
        #expect(try MCPResultEncoderFixtures.rawFragment(bytes,
            path: ["result", "structuredContent", "source", "payload"]) == Data(saved.utf8))
        #expect(env.context.hasChanges)
        #expect(project.name == "Unsaved UI edit")
        #expect(receipt.resultJSON == saved)
        #expect(receipt.expiresAt == expiry)
        #expect(presentation.links.first?.entityId == project.id)
    }

    @Test func seededHistoricalReceiptVariantsReplayWithoutRewritingEvidence() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let args: [String: Any] = ["name": "History", "colorHex": "#112233", "idempotencyKey": "historical-key"]
        _ = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: args))
        let receipt = try #require(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        let expiry = receipt.expiresAt
        let request = receipt.requestJSON
        let original = try #require(receipt.resultJSON)
        try #require(original.last == "}")
        let variants = [
            #", "historical":{"presentation":null,"false":false,"adjacentNull":null,"n":-0.00E+0}"#,
            #", "historical":[false,null,{"unknown":true}],"source":"opaque historic field""#,
            #", "historical":null,"largeInteger":9007199254740993"#
        ]
        for (index, additions) in variants.enumerated() {
            // Add unknown members to a complete valid v1 receipt; never replace its known outcome fields.
            let seeded = String(original.dropLast()) + additions + "}"
            receipt.resultJSON = seeded
            try MCPWriteReceiptStore(context: env.context, scopeID: receipt.localScopeID).validate(receipt)
            try env.context.save()
            let id = "historical-" + String(index)
            let replay = try await MCPModernResultFixture.call(env, tool: "create_project", arguments: args, id: id)
            #expect(try MCPModernResultFixture.text(replay) == seeded)
            let result = try MCPModernResultFixture.assertSource(replay, id: .string(id))
            #expect(MCPResultEncoderFixtures.field("isError", in: result) == nil)
            #expect(receipt.resultJSON == seeded && receipt.resultIsError == false)
            #expect(receipt.expiresAt == expiry && receipt.requestJSON == request)
        }
        // A rejected historic receipt retains its complete rejection evidence and delivered true flag.
        let rejectedArgs: [String: Any] = ["name": "History", "colorHex": "#112233",
                                           "idempotencyKey": "historical-rejected"]
        _ = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: rejectedArgs))
        let rejected = try #require(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>())
            .first { $0.key == "historical-rejected" })
        try #require(rejected.stateRawValue == "rejected" && rejected.resultIsError == true)
        let rejectedOriginal = try #require(rejected.resultJSON)
        try #require(rejectedOriginal.last == "}")
        let rejectedExpiry = rejected.expiresAt
        let rejectedRequest = rejected.requestJSON
        let rejectedSeed = String(rejectedOriginal.dropLast()) + #", "historical":{"retryAction":null,"n":-0.00E+0}}"#
        rejected.resultJSON = rejectedSeed
        try MCPWriteReceiptStore(context: env.context, scopeID: rejected.localScopeID).validate(rejected)
        try env.context.save()
        let replay = try await MCPModernResultFixture.call(env, tool: "create_project",
                                                          arguments: rejectedArgs, id: "rejected-history")
        #expect(try MCPModernResultFixture.text(replay) == rejectedSeed)
        let result = try MCPModernResultFixture.assertSource(replay, id: .string("rejected-history"))
        #expect(MCPResultEncoderFixtures.field("isError", in: result) == .boolean(true))
        #expect(rejected.resultJSON == rejectedSeed && rejected.resultIsError == true)
        #expect(rejected.expiresAt == rejectedExpiry && rejected.requestJSON == rejectedRequest)
    }

    @Test func missingHistoricReceiptFlagUsesExistingUncertaintyWithoutSourceBypass() async throws {
        // Receipt validation remains authoritative: unavailable flags and invalid payloads cannot be replayed.
        let invalidVariants: [(String?, Bool?)] = [(nil, nil), ("null", false),
            (#"{"unknown":1E+9999}"#, false), ("{unreadable retained evidence", false)]
        for (index, variant) in invalidVariants.enumerated() {
            let env = try MCPTestHelpers.makeEnv()
            defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
            let args: [String: Any] = ["name": "Unknown Evidence", "colorHex": "#112233",
                                       "idempotencyKey": "invalid-history-" + String(index)]
            _ = await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: args))
            let receipt = try #require(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
            let original = try #require(receipt.resultJSON)
            let saved = variant.0 ?? original
            let expiry = receipt.expiresAt
            let request = receipt.requestJSON
            receipt.resultJSON = saved
            receipt.resultIsError = variant.1
            try env.context.save()
            let id = "invalid-history-" + String(index)
            let response = try await MCPModernResultFixture.call(env, tool: "create_project", arguments: args, id: id)
            let text = try MCPModernResultFixture.text(response)
            #expect(text != saved && text.contains("OUTCOME_UNCERTAIN"))
            _ = try MCPModernResultFixture.assertSource(response, id: .string(id))
            #expect(receipt.resultJSON == saved && receipt.resultIsError == variant.1)
            #expect(receipt.expiresAt == expiry && receipt.requestJSON == request)
        }
    }

    @Test func actualProtectedPostcommitOuterFailurePreservesReceiptAndReplay() async throws {
        let env = try MCPTestHelpers.makeEnv()
        defer { try? FileManager.default.removeItem(at: env.sidecarDirectory) }
        let handler = env.handler
        let args: [String: Any] = ["name": "  Post Commit\n", "colorHex": "#112233", "idempotencyKey": "postcommit-key"]
        let request = MCPTestHelpers.toolCallRequest(tool: "create_project", arguments: args)
        let fixed = MCPResultContext(tool: "create_project", semanticFailure: nil,
            mutationRecovery: .protectedWrite(.init(tool: "create_project", idempotencyKey: "postcommit-key")),
            entityPositions: [.init(entityType: .project, sourcePath: "/record")])
        let fallback = try MCPResultAdapter.source(text: #"{"error":{"code":"OUTCOME_UNKNOWN"}}"#,
            isError: true, origin: .generatedJSON, evidence: .unestablished)
        let calls = EncoderCount()
        let id = JSONRPCId.string("postcommit-rpc")
        let ready = try MCPResultProviderSelection.prepare(id: id, source: fallback, context: fixed, metadata: nil)
        let selected = try await MCPResultProviderSelection.mutation(id: id, context: fixed,
            metadata: nil, fallbackSource: fallback, encodeOutcome: { _, _, _ in
                calls.record(); throw OuterFailure.encoding
            },
            dispatch: { try await Self.protectedOutcome(handler, request: request, context: fixed) })
        guard case .reconciliation(let bytes) = selected else {
            Issue.record("Expected ready postcommit recovery bytes"); throw OuterFailure.encoding
        }
        #expect(bytes == ready)
        #expect(calls.count == 1)
        let result = try MCPResultEncoderFixtures.result(bytes, id: id)
        let structured = try MCPResultEncoderFixtures.structured(result)
        let presentation = MCPResultEncoderFixtures.field("presentation", in: structured)
        let recovery = MCPResultEncoderFixtures.field("recovery", in: presentation)
        #expect(MCPResultEncoderFixtures.field("idempotencyKey", in: recovery) == .string("postcommit-key"))
        let fresh = ModelContext(env.context.container)
        fresh.autosaveEnabled = false
        let project = try #require(try fresh.fetch(FetchDescriptor<Project>()).first)
        #expect(project.name == "Post Commit")
        let receipt = try #require(try fresh.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        #expect(receipt.stateRawValue == "committed")
        let stored = try #require(receipt.resultJSON)
        let expiry = receipt.expiresAt
        let replay = try await MCPModernResultFixture.call(env, tool: "create_project",
                                                            arguments: args, id: "reconcile-new-id")
        #expect(try MCPModernResultFixture.text(replay) == stored)
        _ = try MCPModernResultFixture.assertSource(replay, id: .string("reconcile-new-id"))
        let after = ModelContext(env.context.container)
        after.autosaveEnabled = false
        let recovered = try #require(try after.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        #expect(recovered.resultJSON == stored)
        #expect(recovered.expiresAt == expiry)
        #expect(recovered.id == receipt.id)
        #expect(try after.fetchCount(FetchDescriptor<Project>()) == 1)
    }

}

extension MCPResultProviderIntegrationTests {
    private enum OuterFailure: Error { case encoding }
    private nonisolated final class EncoderCount: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func record() { lock.lock(); defer { lock.unlock() }; value += 1 }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func assertReadParity(_ env: MCPTestEnv, task: TransitTask, project: Project,
                                  savedRevision: String) async throws {
        project.name = "Relabeled Parent"
        try env.context.save()
        #expect(try MCPTestHelpers.readRevision(task, in: env.context) == savedRevision)
        for includeComments in [false, true] {
            let read = try await MCPModernResultFixture.call(env, tool: "query_tasks", arguments: [
                "taskIds": [task.id.uuidString], "detailLevel": "full", "includeComments": includeComments,
                "readPolicy": "cached"
            ], id: includeComments ? "with-comments" : "without-comments")
            let text = try MCPModernResultFixture.text(read)
            let payload = try MCPJSONDocument.parse(text).value
            guard case .array(let results) = MCPResultEncoderFixtures.field("results", in: payload) else {
                Issue.record("Missing full saved read records"); throw OuterFailure.encoding
            }
            let entry = try #require(results.first)
            let record = try #require(MCPResultEncoderFixtures.field("task", in: entry))
            #expect(MCPResultEncoderFixtures.field("taskId", in: record) == .string(task.id.uuidString))
            #expect(MCPResultEncoderFixtures.field("revision", in: record) == .string(savedRevision))
            #expect(MCPResultEncoderFixtures.field("projectName", in: record) == .string("Relabeled Parent"))
            if includeComments {
                guard case .array(let comments) = MCPResultEncoderFixtures.field("comments", in: record) else {
                    Issue.record("Missing requested comment bodies"); throw OuterFailure.encoding
                }
                #expect(comments.count == 1)
            } else {
                #expect(MCPResultEncoderFixtures.field("comments", in: record) == nil)
            }
            _ = try MCPModernResultFixture.assertSource(read,
                id: .string(includeComments ? "with-comments" : "without-comments"))
        }
    }

    private static func protectedOutcome(_ handler: MCPToolHandler, request: JSONRPCRequest,
                                         context: MCPResultContext) async throws -> MCPResultProviderOutcome {
        let response = try #require(await handler.handle(request))
        let tool = try #require(response.result?.value as? MCPToolResult)
        let text = try #require(tool.content.first?.text)
        let source = try MCPResultAdapter.source(text: text, isError: tool.isError,
                                                 origin: .retainedJSON, evidence: .established)
        return MCPResultProviderOutcome(source: source, context: context)
    }

    private func savedRecord(_ response: MCPHTTPTestResponse) throws -> [String: Any] {
        let text = try MCPModernResultFixture.text(response)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(payload["outcome"] as? String == "committed")
        #expect(payload["accepted"] as? Bool == true)
        return try #require(payload["record"] as? [String: Any])
    }
}
#endif
