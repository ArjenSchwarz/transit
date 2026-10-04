#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPWriteLifecycleTests {
    @Test func protectedRequestPersistsAndReplaysAcrossResponderReplacement() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let key = MCPTestHelpers.freshWriteKey()
        let args: [String: Any] = ["name": "request", "colorHex": "#123456", "idempotencyKey": key]
        let initial = try await MCPModernResultFixture.respond(env, method: "tools/call", id: "original",
            parameters: ["name": "create_project", "arguments": args])
        let initialRPC = try #require(initial.json as? [String: Any])
        #expect(initial.status == .ok && initialRPC["id"] as? String == "original")
        #expect(try MCPTestHelpers.decodeHTTPToolResult(initialRPC)["outcome"] as? String == "committed")
        // Each transport call constructs a new responder while retaining the app-owned retry store.
        let replay = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 7,
            parameters: ["name": "create_project", "arguments": args])
        let replayRPC = try #require(replay.json as? [String: Any])
        let envelope = try MCPTestHelpers.decodeHTTPToolResult(replayRPC)
        #expect(replay.status == .ok && replayRPC["id"] as? Int == 7)
        #expect(envelope["outcome"] as? String == "committed")
        #expect(envelope["accepted"] as? Bool == true)
        let originalText = try MCPModernResultFixture.text(initial)
        let replayText = try MCPModernResultFixture.text(replay)
        #expect(originalText.utf8.elementsEqual(replayText.utf8))
        #expect(try env.context.fetchCount(FetchDescriptor<Project>()) == 1)
        let receipts = try env.context.fetch(FetchDescriptor<MCPWriteReceipt>())
        try #require(receipts.count == 1)
        #expect(receipts[0].resultJSON == originalText)
    }

    @Test(arguments: [false, true])
    func orderedRequestsRetainFirstCommitWhenSecondWriteRejects(distinctKey: Bool) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let key = MCPTestHelpers.freshWriteKey()
        let first = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 1,
            parameters: ["name": "create_project", "arguments": ["name": "first", "colorHex": "#123456",
                "idempotencyKey": key]])
        let second = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 2,
            parameters: ["name": "create_project", "arguments": ["name": "first", "colorHex": "#654321",
                "idempotencyKey": distinctKey ? MCPTestHelpers.freshWriteKey() : key]])
        let firstRPC = try #require(first.json as? [String: Any])
        let secondRPC = try #require(second.json as? [String: Any])
        #expect(first.status == .ok && second.status == .ok)
        #expect(firstRPC["id"] as? Int == 1 && secondRPC["id"] as? Int == 2)
        let committed = try MCPTestHelpers.decodeHTTPToolResult(firstRPC)
        let rejected = try MCPTestHelpers.decodeHTTPToolResult(secondRPC)
        #expect(committed["outcome"] as? String == "committed" && committed["accepted"] as? Bool == true)
        #expect(rejected["outcome"] as? String == "rejected")
        #expect(rejected["accepted"] as? Bool == distinctKey)
        #expect((rejected["error"] as? [String: Any])?["code"] as? String
            == (distinctKey ? "DUPLICATE_PROJECT_NAME" : "IDEMPOTENCY_KEY_REUSED"))
        let projects = try env.context.fetch(FetchDescriptor<Project>())
        #expect(projects.map(\.name) == ["first"])
        #expect(projects.first?.colorHex == "#123456")
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == (distinctKey ? 2 : 1))
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
        try env.context.save()
        let args: [String: Any] = ["name": "disconnect", "type": "feature",
            "projectId": project.id.uuidString, "idempotencyKey": "disconnect"]
        let observation = MCPWriteConnectionObservation()
        let connection = Task { @MainActor in
            do {
                observation.response = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 1,
                    parameters: ["name": "create_task", "arguments": args])
            } catch { observation.failure = String(describing: error) }
            observation.finished = true
        }
        do {
            try await waitForAcceptance(counter, observation: observation)
            // The real allocator suspension occurs only after durable acceptance.
            #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 1)
            connection.cancel()
            await counter.release()
            try #require(await waitForCompletion(observation), "Accepted cancelled request did not drain")
            await connection.value
            let replay = try await MCPModernResultFixture.respond(env, method: "tools/call", id: "replay",
                parameters: ["name": "create_task", "arguments": args])
            let rpc = try #require(replay.json as? [String: Any])
            #expect(rpc["id"] as? String == "replay")
            let result = try MCPTestHelpers.decodeHTTPToolResult(rpc)
            #expect(result["outcome"] as? String == "rejected")
            #expect(result["accepted"] as? Bool == true)
            #expect((result["error"] as? [String: Any])?["code"] as? String == "CANCELLED")
            #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
            let receipts = try env.context.fetch(FetchDescriptor<MCPWriteReceipt>())
            try #require(receipts.count == 1)
            let stored = try #require(receipts[0].resultJSON)
            let replayText = try MCPModernResultFixture.text(replay)
            #expect(stored.utf8.elementsEqual(replayText.utf8))
            #expect(await counter.loadCount() == 1)
        } catch {
            connection.cancel()
            await counter.release()
            let drained = await waitForCompletion(observation)
            #expect(drained, "Failed cancellation fixture must drain its released connection")
            if drained { await connection.value }
            throw error
        }
    }

    private func waitForAcceptance(_ counter: MCPWriteLifecycleCounter,
                                   observation: MCPWriteConnectionObservation) async throws {
        let cutoff = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < cutoff {
            if await counter.hasStarted() { return }
            if observation.finished {
                Issue.record("Request completed before allocator acceptance: \(observation.evidence)")
                throw MCPWriteLifecycleFixtureError.notAccepted
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Allocator acceptance deadline expired: \(observation.evidence)")
        throw MCPWriteLifecycleFixtureError.notAccepted
    }

    private func waitForCompletion(_ observation: MCPWriteConnectionObservation) async -> Bool {
        let cutoff = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < cutoff {
            if observation.finished { return true }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return observation.finished }
        }
        return observation.finished
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
@MainActor private final class MCPWriteConnectionObservation {
    var response: MCPHTTPTestResponse?
    var failure: String?
    var finished = false
    var evidence: String {
        if let response {
            let body = String(data: response.body.prefix(1024), encoding: .utf8) ?? "<non-UTF8>"
            return "HTTP \(response.status), body \(body)"
        }
        return failure ?? "request still running"
    }
}
private enum MCPWriteLifecycleFixtureError: Error { case notAccepted }

actor MCPWriteLifecycleCounter: DisplayIDAllocator.CounterStore {
    private var continuation: CheckedContinuation<Void, Never>?
    private var loads = 0
    private var released = false

    func waitForLoad() async {
        let cutoff = ContinuousClock.now.advanced(by: .seconds(2))
        while loads == 0 && ContinuousClock.now < cutoff {
            do { try await Task.sleep(for: .milliseconds(10)) } catch {
                Issue.record("Allocator rendezvous cancelled before entry")
                return
            }
        }
        if loads == 0 { Issue.record("Allocator rendezvous expired before entry") }
    }

    func hasStarted() -> Bool { loads > 0 }
    func loadCount() -> Int { loads }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        loads += 1
        if !released { await withCheckedContinuation { continuation = $0 } }
        return .init(nextDisplayID: 1, changeTag: nil)
    }
    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws { }
}
#endif
