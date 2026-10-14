#if os(macOS)
import Foundation
import Testing
@testable import Transit

@Suite(.serialized)
nonisolated struct MCPReadFailureJournalTests {
    @Test @concurrent func timeoutEvidenceArrivesWhileMainActorRemainsBlocked() async throws {
        let recorder = MCPReadDiagnosticRecorder()
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("failure.json")
        let journal = MCPReadFailureJournal(url: url)
        let sink = MCPReadDiagnosticSink { event in
            if let failure = event.failure { try? journal.append(failure) }
            recorder.append(event)
        }
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(40), diagnostics: sink)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Task { @MainActor in
            Self.blockMainActor(started: started, finished: finished)
        }
        try #require(Self.wait(started, seconds: 1) == .success)
        let response = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data()) { operation in
            operation.beginActorQueue()
            return await MainActor.run { Self.prepared() }
        }
        #expect(response == Data("timeout".utf8))
        let deadline = ContinuousClock.now + .milliseconds(150)
        while !recorder.events.contains(where: { $0.failure != nil }) && .now < deadline { await Task.yield() }
        let failure = try #require(recorder.events.compactMap(\.failure).first)
        #expect(failure.phase == "queue" && failure.reason == "deadline")
        #expect(failure.physicalCount == 1 && failure.oldestWorkerAgeMs >= 30)
        #expect(failure.processUptimeMs.map { $0 >= 0 } ?? true)
        let saved = try JSONDecoder().decode([MCPReadFailureSnapshot].self, from: Data(contentsOf: url))
        #expect(saved.count == 1 && saved[0].phase == "queue")
        #expect(Self.wait(finished, seconds: 0) == .timedOut)
        try #require(Self.wait(finished, seconds: 1) == .success)
        await drain(coordinator)
    }

    @Test @concurrent func blockedCaptureAndBusyRecordOldestPhysicalWorker() async throws {
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink { recorder.append($0) }
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(40), maxOperations: 1, diagnostics: sink)
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let request = Task.detached {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data(),
                                      diagnosticTool: "query_tasks") { operation in
                operation.beginPhase(.capture)
                started.signal()
                _ = Self.wait(release, seconds: 2)
                return Self.prepared()
            }
        }
        try #require(Self.wait(started, seconds: 1) == .success)
        #expect(await request.value == Data("timeout".utf8))
        let busy = await coordinator.execute(timeout: Data(), busy: Data("busy".utf8)) { _ in Self.prepared() }
        #expect(busy == Data("busy".utf8) && coordinator.unfinishedCount == 1)
        let deadline = ContinuousClock.now + .seconds(1)
        while recorder.events.compactMap(\.failure).count < 2 && .now < deadline { await Task.yield() }
        let failures = recorder.events.compactMap(\.failure)
        #expect(failures.contains { $0.phase == "capture" && $0.phaseAgeMs >= 30 })
        #expect(failures.contains { $0.outcome == "busy" && $0.reason == "admission"
            && $0.oldestWorkerAgeMs >= 30 && $0.physicalCount == 1 })
        release.signal()
        await drain(coordinator)
    }

    @Test @concurrent func lifecycleFailureIsDistinguishedAndRetainsPhysicalOwnership() async throws {
        let recorder = MCPReadDiagnosticRecorder()
        let coordinator = MCPReadCoordinator(diagnostics: MCPReadDiagnosticSink { recorder.append($0) })
        let release = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let request = Task.detached {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data()) { operation in
                operation.beginPhase(.capture)
                started.signal()
                _ = Self.wait(release, seconds: 2)
                return Self.prepared()
            }
        }
        try #require(Self.wait(started, seconds: 1) == .success)
        coordinator.changeLifecycle(.stopApplication)
        #expect(await request.value == Data("timeout".utf8))
        #expect(coordinator.unfinishedCount == 1)
        let deadline = ContinuousClock.now + .seconds(1)
        while recorder.events.compactMap(\.failure).isEmpty && .now < deadline { await Task.yield() }
        #expect(recorder.events.compactMap(\.failure).first?.reason == "lifecycle")
        release.signal()
        await drain(coordinator)
    }

    @Test @concurrent func failureRetiresOrdinaryQueuedEventAndCountsDrops() async throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink(capacity: 2) { event in
            recorder.append(event)
            if recorder.events.count == 1 {
                entered.signal()
                _ = Self.wait(release, seconds: 2)
            }
        }
        let now = ContinuousClock.now
        let context = MCPReadDiagnosticContext(operationID: UUID(), tool: "query_tasks", generation: 1,
            admittedAt: now, responseDeadline: now + .seconds(5), internalCutoff: now + .milliseconds(40))
        let ordinary = MCPReadDiagnosticEvent(context: context, phase: .queue, startedAt: now,
                                             finishedAt: now, outcome: nil, unfinishedPhysicalCount: 1)
        #expect(sink.enqueue(ordinary))
        try #require(Self.wait(entered, seconds: 1) == .success)
        #expect(sink.enqueue(ordinary))
        var failure = ordinary
        failure.failure = snapshot(generation: 1)
        #expect(sink.enqueue(failure))
        #expect(sink.pendingCount == 2 && sink.droppedCount == 1)
        #expect(!sink.enqueue(failure) && sink.droppedCount == 2)
        release.signal()
        let deadline = ContinuousClock.now + .seconds(1)
        while sink.pendingCount != 0 && .now < deadline { await Task.yield() }
        #expect(sink.pendingCount == 0)
        #expect(recorder.events.compactMap(\.failure).first?.droppedEvents == 2)
    }

    @MainActor @Test func preparedBusyResultIsJournaledBeforeDeadline() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.handler.setTaskQueryAdmission(open: false)
        let recorder = MCPReadDiagnosticRecorder()
        let coordinator = MCPReadCoordinator(diagnostics: MCPReadDiagnosticSink { recorder.append($0) })
        let rpc = JSONRPCRequest(jsonrpc: "2.0", id: .string("busy-fixture"), method: "tools/call", params: AnyCodable([
            "name": "query_tasks", "arguments": ["detailLevel": "summary", "includeComments": false, "limit": 1]
        ]))
        let read = try #require(MCPBoundedReadDispatcher.classify(rpc))
        let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc, handler: env.handler,
                                                               coordinator: coordinator, admittedAt: .now)
        let payload = try MCPReadContractFixture.payload(bytes)
        #expect((payload["error"] as? [String: Any])?["code"] as? String == "READ_BUSY")
        await drain(coordinator)
        let deadline = ContinuousClock.now + .seconds(1)
        while recorder.events.compactMap(\.failure).isEmpty && .now < deadline { await Task.yield() }
        #expect(recorder.events.compactMap(\.failure).contains { $0.outcome == "busy" && $0.reason == "admission" })
    }

    @Test @concurrent func pendingFallbackLifecycleReasonIsPreserved() async {
        let recorder = MCPReadDiagnosticRecorder()
        let coordinator = MCPReadCoordinator(diagnostics: MCPReadDiagnosticSink { recorder.append($0) })
        let work = MCPReadBatchWork(timeout: Data("0".utf8), busy: Data("-1".utf8), responds: true) { _ in
            Issue.record("Invalidated batch dispatched work")
            return Self.prepared()
        }
        let bytes = await coordinator.executeBatch([.read(work)], beforeFallbackReady: {
            coordinator.changeLifecycle(.stopApplication)
            coordinator.changeLifecycle(.startApplication)
        }, assemble: { _ in Self.prepared() })
        #expect(bytes == Data("[0]".utf8))
        await drain(coordinator)
        let deadline = ContinuousClock.now + .seconds(1)
        while recorder.events.compactMap(\.failure).isEmpty && .now < deadline { await Task.yield() }
        #expect(recorder.events.compactMap(\.failure).first?.reason == "lifecycle")
    }

    @Test func journalBoundsReloadAndRedaction() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("failures.json")
        let journal = MCPReadFailureJournal(url: url)
        for index in 0..<70 { try journal.append(snapshot(generation: UInt64(index))) }
        let data = try Data(contentsOf: url)
        #expect(data.count <= MCPReadFailureJournal.byteLimit)
        let rows = try JSONDecoder().decode([MCPReadFailureSnapshot].self, from: data)
        #expect(rows.count == 64 && rows.first?.generation == 6 && rows.last?.generation == 69)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("T-2455") && !text.contains("secret") && !text.contains("taskId"))
        #expect(rows.allSatisfy { $0.tool == "unknown" })
        try MCPReadFailureJournal(url: url).append(snapshot(generation: 70))
        let reloaded = try JSONDecoder().decode([MCPReadFailureSnapshot].self, from: Data(contentsOf: url))
        #expect(reloaded.count == 64 && reloaded.first?.generation == 7)
        var untrusted = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        untrusted[0]["tool"] = "secret task contents"
        try JSONSerialization.data(withJSONObject: untrusted).write(to: url)
        try MCPReadFailureJournal(url: url).append(snapshot(generation: 71))
        let cleaned = try JSONDecoder().decode([MCPReadFailureSnapshot].self, from: Data(contentsOf: url))
        #expect(cleaned.count == 1 && cleaned[0].tool == "unknown")
        try Data(repeating: 65, count: MCPReadFailureJournal.byteLimit + 1).write(to: url)
        try MCPReadFailureJournal(url: url).append(snapshot(generation: 71))
        #expect(try JSONDecoder().decode([MCPReadFailureSnapshot].self, from: Data(contentsOf: url)).count == 1)
    }

    private func snapshot(generation: UInt64) -> MCPReadFailureSnapshot {
        MCPReadFailureSnapshot(tool: "T-2455 secret taskId", phase: .capture, outcome: .timeout,
            generation: generation, processUptimeMs: 20, phaseAgeMs: 40, oldestWorkerAgeMs: 50, physicalCount: 1)
    }

    @MainActor private static func blockMainActor(started: DispatchSemaphore, finished: DispatchSemaphore) {
        started.signal()
        Thread.sleep(forTimeInterval: 0.3)
        finished.signal()
    }

    private static func wait(_ semaphore: DispatchSemaphore, seconds: Double) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + seconds)
    }

    private static func prepared() -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data("late".utf8), publications: [],
                          publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }

    private func drain(_ coordinator: MCPReadCoordinator) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
    }
}
#endif
