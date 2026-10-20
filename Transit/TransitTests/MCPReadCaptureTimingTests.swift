#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadCaptureTimingTests {
    @Test func instrumentationPreservesSavedCanonicalRecordsAndRevisions() async throws {
        let owner = try TestModelContainer()
        let project = Project(name: "Fixture", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Fixture task", type: .bug, project: project, displayID: .permanent(1))
        owner.context.insert(project)
        owner.context.insert(task)
        owner.context.insert(Comment(content: "Fixture comment", authorName: "Fixture", isAgent: true, task: task))
        try owner.context.save()
        let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture)
        let request = ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
                                         completeness: .selectedRead, includeComments: true)
        let plain = try builder.capture(request)
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink { recorder.append($0) }
        let coordinator = MCPReadCoordinator(diagnostics: sink)
        _ = await coordinator.execute(timeout: Data(), busy: Data()) { operation in
            await MainActor.run {
                var measured = request
                measured.diagnosticOperation = operation
                do {
                    let value = try builder.capture(measured)
                    #expect(value.tasks.map(\.selectedRecordJSON) == plain.tasks.map(\.selectedRecordJSON))
                    #expect(value.tasks.map(\.revision) == plain.tasks.map(\.revision))
                    #expect(value.comments.map(\.selectedRecordJSON) == plain.comments.map(\.selectedRecordJSON))
                    #expect(value.captureScope == plain.captureScope)
                    #expect(value.metadata.read.budgetMs == plain.metadata.read.budgetMs)
                } catch { Issue.record("Instrumented fixture capture failed") }
                return Self.prepared("success")
            }
        }
        await Self.drain(coordinator, sink: sink)
        #expect(recorder.events.contains { $0.phase == .captureCommentFetch && $0.outcome == .success })
        #expect(!owner.context.hasChanges)
    }

    @Test func throwingFetchReportsOnlyMeasuredFailureAndPreservesError() async throws {
        let owner = try TestModelContainer()
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink { recorder.append($0) }
        let coordinator = MCPReadCoordinator(diagnostics: sink)
        let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture,
                                            fetchTasks: { _ in throw FixtureFailure.expected })
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data()) { operation in
            await MainActor.run {
                var request = Self.request()
                request.diagnosticOperation = operation
                do {
                    _ = try builder.capture(request)
                    Issue.record("Throwing task fetch unexpectedly succeeded")
                } catch {
                    #expect(error as? MCPReadCaptureError == .storageFailure)
                }
                return Self.prepared("failed")
            }
        }
        #expect(bytes == Data("failed".utf8))
        await Self.drain(coordinator, sink: sink)
        let stages = recorder.events.filter { $0.phase.rawValue.hasPrefix("capture") }
        #expect(stages.map(\.phase) == [.captureHistoryBefore, .captureContext, .captureProjects,
                                      .captureMilestones, .captureTasks])
        #expect(stages.last?.outcome == .failure)
        #expect(!stages.contains { $0.phase == .captureGraph || $0.phase == .captureHistoryAfter })
    }

    @Test @concurrent nonisolated func blockedFetchNamesActiveStageBeforePhysicalCompletion() async throws {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let recorder = MCPReadDiagnosticRecorder()
        let sink = MCPReadDiagnosticSink { recorder.append($0) }
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(40), maxOperations: 1, diagnostics: sink)
        let (owner, builder) = try await MainActor.run {
            let owner = try TestModelContainer()
            let builder = MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture,
                fetchTasks: { _ in
                    started.signal()
                    #expect(release.wait(timeout: .now() + 2) == .success)
                    return []
                })
            return (owner, builder)
        }
        defer { withExtendedLifetime(owner) {} }
        let call = Task.detached {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data(),
                                      diagnosticTool: "query_tasks") { operation in
                await MainActor.run {
                    var request = Self.request()
                    request.diagnosticOperation = operation
                    do { _ = try builder.capture(request) } catch { Issue.record("Unexpected fixture error") }
                    return Self.prepared("late")
                }
            }
        }
        try #require(MCPReadContractFixture.wait(started, seconds: 1) == .success)
        #expect(await call.value == Data("timeout".utf8))
        #expect(coordinator.unfinishedCount == 1)
        let timeoutDeadline = ContinuousClock.now + .seconds(1)
        while recorder.events.compactMap(\.failure).isEmpty && .now < timeoutDeadline { await Task.yield() }
        let failure = try #require(recorder.events.compactMap(\.failure).first)
        #expect(failure.phase == "captureTasks" && failure.hasSafeSchema)
        #expect(failure.phaseAgeMs > 0 && failure.physicalCount == 1)
        #expect(!recorder.events.contains { $0.phase == .captureTasks })
        release.signal()
        await Self.drain(coordinator, sink: sink)
        let stage = try #require(recorder.events.first { $0.phase == .captureTasks })
        #expect(stage.outcome == .success && stage.finishedAt > stage.startedAt)
        #expect(recorder.events.contains { $0.phase == .physicalFinish && $0.unfinishedPhysicalCount == 0 })
        #expect(recorder.events.contains { $0.outcome == .discarded || $0.outcome == .lateCompletion })
    }

    @Test func allStageNamesAreSafeAndPrivateStringsAreRejected() throws {
        let stages: [MCPReadDiagnosticPhase] = [.captureHistoryBefore, .captureContext, .captureProjects,
            .captureMilestones,
            .captureTasks, .captureGraph, .captureSelection, .captureCommentFetch, .captureCommentIndex,
            .captureRecords, .captureConsolidation, .captureHistoryAfter, .captureValidation]
        for phase in stages {
            let snapshot = MCPReadFailureSnapshot(tool: "query_tasks", phase: phase, outcome: .timeout,
                generation: 1, processUptimeMs: 1, admissionElapsedMs: 5_000, cutoffOverrunMs: 150,
                phaseAgeMs: 1, oldestWorkerAgeMs: 5_000, physicalCount: 1)
            #expect(snapshot.hasSafeSchema)
            let data = try JSONEncoder().encode(snapshot)
            var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["phase"] = "private task content"
            let poisoned = try JSONDecoder().decode(MCPReadFailureSnapshot.self,
                from: JSONSerialization.data(withJSONObject: json))
            #expect(!poisoned.hasSafeSchema)
        }
    }

    private static func request() -> ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .summary), completeness: .selectedRead,
                           includeComments: false)
    }

    nonisolated private static func prepared(_ value: String) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data(value.utf8), publications: [],
                           publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }

    nonisolated private static func drain(_ coordinator: MCPReadCoordinator, sink: MCPReadDiagnosticSink) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while (coordinator.unfinishedCount != 0 || sink.pendingCount != 0) && .now < deadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0 && sink.pendingCount == 0)
    }

    private enum FixtureFailure: Error { case expected }
}
#endif
