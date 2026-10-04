#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Independent task 14 preparation. No runtime RED or task 15 instrumentation is supplied yet.
@MainActor @Suite(.serialized)
struct MCPReadDiagnosticsTests {
    @Test func disabledSinkDoesNoWork() {
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink(capacity: 0, writer: { recorder.append($0) })
        #expect(!sink.enqueue(event()))
        #expect(sink.pendingCount == 0 && recorder.events.isEmpty)
    }

    @Test func savedReadReportsActualPhasesWithOriginalCorrelation() async throws {
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink(writer: { recorder.append($0) })
        let fixture = try MCPReadContractFixture(diagnostics: sink)
        let id = UUID()
        _ = try await fixture.execute(arguments: ["detailLevel": "summary", "includeComments": false,
                                                  "limit": 1], operationID: id)
        await fixture.drain()
        let events = await waitForEvents(recorder, phase: .physicalFinish)
        for phase in [MCPReadDiagnosticPhase.queue, .refresh, .capture, .transform, .serialization, .terminal] {
            #expect(events.contains { $0.phase == phase })
        }
        for value in events {
            #expect(value.context.operationID == id && value.context.tool == "query_tasks")
            #expect(value.context.generation > 0)
            #expect(value.context.responseDeadline == value.context.admittedAt + .seconds(5))
            #expect(value.context.internalCutoff == value.context.admittedAt + .milliseconds(4_850))
            #expect(value.startedAt >= value.context.admittedAt && value.finishedAt >= value.startedAt)
            #expect(value.unfinishedPhysicalCount >= 0 && value.unfinishedPhysicalCount <= 8)
        }
        #expect(events.contains { $0.phase == .physicalFinish && $0.unfinishedPhysicalCount == 0 })
        // A single request must not invent an aggregation measurement for nonexistent wire-array work.
        #expect(!events.contains { $0.phase == .aggregation })
    }

    @Test func blockedWriterKeepsQueueBoundedAndCannotDelayTimerOrHoldDomain() async {
        let entered = DispatchSemaphore(value: 0)
        let loggingRelease = DispatchSemaphore(value: 0)
        let workerRelease = DispatchSemaphore(value: 0)
        let workerStarted = DispatchSemaphore(value: 0)
        let recorded = MCPReadDiagnosticRecorder()
        defer { loggingRelease.signal(); workerRelease.signal() }
        let sink = MCPReadDiagnosticSink(capacity: 2) { value in
            recorded.append(value)
            guard recorded.events.count == 1 else { return }
            entered.signal()
            let released = loggingRelease.wait(timeout: .now() + 2)
            #expect(released == .success)
        }
        let before = ContinuousClock.now
        #expect(sink.enqueue(event()))
        #expect(before.duration(to: .now) < .milliseconds(100))
        let loggingStarted = await Task.detached { MCPReadContractFixture.wait(entered, seconds: 0.2) }.value
        #expect(loggingStarted == .success)
        #expect(sink.enqueue(event()))
        #expect(!sink.enqueue(event()))
        #expect(sink.pendingCount <= 2)
        let domain = MCPReadPublicationDomain()
        let coordinator = MCPReadCoordinator(domain: domain, cutoff: .milliseconds(30), diagnostics: sink)
        let start = ContinuousClock.now
        let call = Task.detached {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                                      diagnosticTool: "query_tasks") { _ in
                workerStarted.signal()
                let released = await Task.detached { MCPReadContractFixture.wait(workerRelease, seconds: 2) }.value
                #expect(released == .success)
                return Self.prepared(Data("late".utf8))
            }
        }
        let started = await Task.detached { MCPReadContractFixture.wait(workerStarted, seconds: 1) }.value
        #expect(started == .success)
        let bytes = await call.value
        #expect(bytes == Data("timeout".utf8) && start.duration(to: .now) < .milliseconds(200))
        let lockStart = ContinuousClock.now
        #expect(coordinator.unfinishedCount == 1)
        #expect(lockStart.duration(to: .now) < .milliseconds(100))
        workerRelease.signal()
        loggingRelease.signal()
        await drain(coordinator)
        let sinkDeadline = ContinuousClock.now + .seconds(1)
        while sink.pendingCount != 0 && .now < sinkDeadline { await Task.yield() }
        #expect(sink.pendingCount == 0)
    }

    @Test func timeoutAndLateFinalizerKeepOriginalIdentityAndPhysicalCount() async {
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink(writer: { recorder.append($0) })
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(30), maxOperations: 1, diagnostics: sink)
        let gate = DispatchSemaphore(value: 0)
        let workerStarted = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let id = UUID()
        let call = Task.detached {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                admission: MCPReadAdmission(operationID: id), diagnosticTool: "query_tasks") { _ in
                workerStarted.signal()
                let released = await Task.detached { MCPReadContractFixture.wait(gate, seconds: 2) }.value
                #expect(released == .success)
                return Self.prepared(Data("discarded-late-result".utf8))
            }
        }
        let started = await Task.detached { MCPReadContractFixture.wait(workerStarted, seconds: 1) }.value
        #expect(started == .success)
        let bytes = await call.value
        #expect(bytes == Data("timeout".utf8) && coordinator.unfinishedCount == 1)
        gate.signal()
        await drain(coordinator)
        let events = await waitForEvents(recorder, phase: .physicalFinish)
        #expect(events.contains { $0.phase == .terminal && $0.outcome == .timeout
            && $0.unfinishedPhysicalCount == 1 })
        #expect(events.contains { $0.outcome == .discarded || $0.outcome == .lateCompletion })
        #expect(events.contains { $0.phase == .physicalFinish && $0.unfinishedPhysicalCount == 0 })
        #expect(events.allSatisfy { $0.context.operationID == id && $0.context.tool == "query_tasks" })
    }

    /// Historical coordinator assembly proof only; modern production rejects wire arrays.
    @Test func historicalComponentAggregationReportsItsMeasuredInterval() async throws {
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink(writer: { recorder.append($0) })
        let coordinator = MCPReadCoordinator(diagnostics: sink)
        let admittedAt = ContinuousClock.now
        let elements = [1, 2].map { number in
            MCPReadBatchElement.read(MCPReadBatchWork(timeout: Data("timeout".utf8),
                busy: Data("busy".utf8), responds: true) { _ in
                Self.prepared(Data("\(number)".utf8))
            })
        }
        let bytes = await coordinator.executeBatch(elements, admittedAt: admittedAt) { values in
            Self.prepared(MCPReadBatchEncoding.array(values.map { $0?.encodedResponse }) ?? Data())
        }
        #expect(bytes == Data("[1,2]".utf8))
        await drain(coordinator)
        let values = await waitForEvents(recorder, phase: .aggregation)
        let intervals = values.filter { $0.phase == .aggregation }
        #expect(intervals.count == 1)
        for interval in intervals {
            #expect(interval.context.admittedAt == admittedAt)
            #expect(interval.startedAt >= admittedAt && interval.finishedAt >= interval.startedAt)
        }
    }

    private func event() -> MCPReadDiagnosticEvent {
        let start = ContinuousClock.now
        return MCPReadDiagnosticEvent(context: MCPReadDiagnosticContext(operationID: UUID(), tool: "query_tasks",
            generation: 1, admittedAt: start, responseDeadline: start + .seconds(5),
            internalCutoff: start + .milliseconds(4_850)), phase: .queue,
            startedAt: start, finishedAt: .now, outcome: nil, unfinishedPhysicalCount: 1)
    }

    private func waitForEvents(_ recorder: MCPReadDiagnosticRecorder,
                               phase: MCPReadDiagnosticPhase) async -> [MCPReadDiagnosticEvent] {
        let deadline = ContinuousClock.now + .seconds(1)
        while !recorder.events.contains(where: { $0.phase == phase }) && .now < deadline { await Task.yield() }
        return recorder.events
    }

    private func drain(_ coordinator: MCPReadCoordinator) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
    }

    nonisolated private static func prepared(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
                           publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }
}
#endif
