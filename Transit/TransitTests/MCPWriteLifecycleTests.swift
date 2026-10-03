#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPWriteLifecycleTests {
    @Test func protectedNotificationPersistsAndReplaysAcrossResponderReplacement() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let key = MCPTestHelpers.freshWriteKey()
        let args: [String: Any] = ["name": "notification", "colorHex": "#123456", "idempotencyKey": key]
        let notification: [String: Any] = ["jsonrpc": "2.0", "method": "tools/call",
                                          "params": ["name": "create_project", "arguments": args]]
        let data = try JSONSerialization.data(withJSONObject: notification)
        let body = try #require(String(data: data, encoding: .utf8))
        let response = try await MCPTestHelpers.respond(handler: env.handler, contentType: "application/json",
                                                        body: body, loggerLabel: "write.notification")
        #expect(response.status == .accepted)
        #expect(response.body.isEmpty)
        let retry: [String: Any] = ["jsonrpc": "2.0", "id": 7, "method": "tools/call",
                                   "params": ["name": "create_project", "arguments": args]]
        let retryData = try JSONSerialization.data(withJSONObject: retry)
        let retryBody = try #require(String(data: retryData, encoding: .utf8))
        let replay = try await MCPTestHelpers.respond(handler: env.handler, contentType: "application/json",
                                                      body: retryBody, loggerLabel: "write.notification.replay")
        let envelope = try MCPTestHelpers.decodeHTTPToolResult(try #require(replay.json as? [String: Any]))
        #expect(envelope["outcome"] as? String == "committed")
        #expect(try env.context.fetch(FetchDescriptor<Project>()).count == 1)
        #expect(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).count == 1)
    }

    @Test func orderedBatchRetainsFirstCommitWhenSecondWriteRejects() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let body = """
        [
          {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_project",
          "arguments":{"name":"first","colorHex":"#123456","idempotencyKey":"batch-first"}}},
          {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_project",
          "arguments":{"name":"first","colorHex":"#123456","idempotencyKey":"batch-second"}}}
        ]
        """
        let response = try await MCPTestHelpers.respond(handler: env.handler, contentType: "application/json",
                                                        body: body, loggerLabel: "write.batch")
        let objects = try #require(response.json as? [[String: Any]])
        #expect(objects.count == 2)
        #expect(try MCPTestHelpers.decodeHTTPToolResult(objects[0])["outcome"] as? String == "committed")
        #expect(try MCPTestHelpers.decodeHTTPToolResult(objects[1])["outcome"] as? String == "rejected")
        #expect(try env.context.fetch(FetchDescriptor<Project>()).map(\.name) == ["first"])
    }

    @Test func localAndSeparatelySavedChangesInvalidateObservedRevision() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(name: "original", description: nil, type: .feature,
                                                       project: project)
        let original = try MCPTestHelpers.readRevision(task, in: env.context)
        try env.taskService.updateTask(task, name: "UI edit")
        #expect(try MCPTestHelpers.readRevision(task, in: env.context) != original)
        let peer = ModelContext(env.context.container)
        let taskID = task.id
        let descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == taskID })
        let imported = try #require(try peer.fetch(descriptor).first)
        let before = try MCPRecordSnapshot.task(imported, in: peer).revision
        imported.name = "separately saved"
        try peer.save()
        let observer = ModelContext(env.context.container)
        let observed = try #require(try observer.fetch(descriptor).first)
        #expect(try MCPRecordSnapshot.task(observed, in: observer).revision != before)
    }

    @Test func disconnectedRequestKeepsAcceptedCancellationForReplay() async throws {
        let counter = MCPWriteLifecycleCounter()
        let env = try MCPTestHelpers.makeEnv(taskCounterStore: counter)
        let project = MCPTestHelpers.makeProject(in: env.context)
        let args: [String: Any] = ["name": "disconnect", "type": "feature",
                                  "projectId": project.id.uuidString, "idempotencyKey": "disconnect"]
        let request = MCPTestHelpers.toolCallRequest(tool: "create_task", arguments: args)
        let object: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                    "params": ["name": "create_task", "arguments": args]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let body = try #require(String(data: data, encoding: .utf8))
        let connection = Task {
            try await MCPTestHelpers.respond(handler: env.handler, contentType: "application/json",
                                              body: body, loggerLabel: "write.disconnect")
        }
        await counter.waitForLoad()
        connection.cancel()
        await counter.release()
        _ = try? await connection.value
        let replay = await env.handler.handle(request)
        let result = try MCPTestHelpers.decodeResult(replay)
        #expect(result["accepted"] as? Bool == true)
        #expect(try MCPTestHelpers.errorCode(replay) == "CANCELLED")
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        #expect(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).count == 1)
    }

    @Test func missingSafetyIsRejectedWithoutReservingAKey() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_project", arguments: ["name": "raw", "colorHex": "#123456"]
        ))
        let result = try MCPTestHelpers.decodeResult(response)
        #expect((result["error"] as? [String: Any])?["code"] as? String == "INVALID_INPUT")
        #expect(result["accepted"] as? Bool == false)
        #expect(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
    }
}
actor MCPWriteLifecycleCounter: DisplayIDAllocator.CounterStore {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var started = false

    func waitForLoad() async {
        if started { return }
        await withCheckedContinuation { observer = $0 }
    }

    func release() { continuation?.resume(); continuation = nil }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        started = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { continuation = $0 }
        return .init(nextDisplayID: 1, changeTag: nil)
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws { }
}
#endif
