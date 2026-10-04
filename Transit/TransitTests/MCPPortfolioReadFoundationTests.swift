#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOConcurrencyHelpers
import NIOFoundationCompat
import SwiftData
import Testing
@testable import Transit

@Suite(.serialized)
nonisolated struct MCPPortfolioReadFoundationTests {
    @Test @MainActor func reusableCaptureAdapterEncodesAllEvidenceAndPreservesPendingEdits() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let original = try fixture.capture()
        fixture.project.name = "Unsaved project"
        fixture.tasks[6].taskDescription = "Unsaved description"
        fixture.comment.content = "Unsaved body"
        let saved = try fixture.capture()
        #expect(saved.projects.first { $0.id == fixture.project.id }?.name == "Populated")
        #expect(saved.tasks.first { $0.id == fixture.tasks[6].id }?.revision
                == original.tasks.first { $0.id == fixture.tasks[6].id }?.revision)
        #expect(saved.comments.first?.content == "Canonical comment coverage")
        #expect(fixture.owner.context.hasChanges)
        let result = try MCPPortfolioFoundationHarness.prepareCapture(saved)
        let envelope = try #require(try JSONSerialization.jsonObject(with: result.encodedResponse) as? [String: Any])
        #expect(envelope["taskCount"] as? Int == 9)
        #expect((envelope["records"] as? [String])?.count == 9)
        #expect(envelope["snapshotId"] as? String == saved.metadata.snapshotId)
        #expect(envelope["asOf"] as? String == saved.metadata.asOf)
        #expect(result.publications.isEmpty)
    }

    // swiftlint:disable:next function_body_length
    @Test @concurrent func actualRouterBoundsComplete2375TaskCaptureAndRevisionEncoding() async throws {
        let setupStart = ContinuousClock.now
        let fixture = try await MainActor.run {
            try MCPPortfolioSavedFixture(taskCount: 2_375, commentOnEveryTask: true)
        }
        print("PORTFOLIO_VOLUME fixture_setup_elapsed=\(setupStart.duration(to: .now))")
        let coordinator = MCPReadCoordinator()
        let completion = PortfolioFoundationCompletion()
        let start = ContinuousClock.now
        let bytes = try await MCPPortfolioFoundationHarness.route {
            await MCPReadTransportAdapter.response(coordinator: coordinator,
                timeout: MCPPortfolioFoundationHarness.timeout, busy: MCPPortfolioFoundationHarness.busy) { _ in
                let physicalStart = ContinuousClock.now
                let result: PreparedReadResult
                do {
                    let view = try await MainActor.run { try fixture.capture() }
                    print("PORTFOLIO_VOLUME saved_capture_elapsed=\(physicalStart.duration(to: .now))")
                    #expect(view.tasks.count == 2_375 && view.comments.count == 2_376)
                    #expect(view.captureScope == .wholePortfolio)
                    #expect(view.tasks.allSatisfy {
                        $0.revision?.hasPrefix("r1:") == true && $0.fullRecordWithoutCommentsJSON != nil
                            && !$0.commentKeys.isEmpty && $0.requestedCommentRecordsJSON == nil
                    })
                    result = try MCPPortfolioFoundationHarness.prepareCapture(view)
                    print("PORTFOLIO_VOLUME encoded_full_envelope_bytes=\(result.encodedResponse.count) "
                          + "canonical_records=\(view.tasks.count) comment_evidence=\(view.comments.count)")
                } catch {
                    Issue.record("Portfolio capture/adapter failed: \(error)")
                    result = MCPPortfolioFoundationHarness.result(MCPPortfolioFoundationHarness.busy)
                }
                print("PORTFOLIO_VOLUME capture_and_encode_physical_elapsed=\(physicalStart.duration(to: .now))")
                await completion.finish()
                return result
            }
        }
        let elapsed = start.duration(to: .now)
        print("PORTFOLIO_VOLUME router_and_body_elapsed=\(elapsed) tasks=2375 bytes=\(bytes.count)")
        #expect(elapsed <= .seconds(5))
        if bytes != MCPPortfolioFoundationHarness.timeout && bytes != MCPPortfolioFoundationHarness.capacity {
            let envelope = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(envelope["taskCount"] as? Int == 2_375)
            #expect((envelope["records"] as? [String])?.count == 2_375)
            #expect((envelope["taskEvidence"] as? [[String: Any]])?.count == 2_375)
            #expect((envelope["comments"] as? [[String: Any]])?.count == 2_376)
        }
        // Await physical completion before releasing the shared test slot or owning fixture.
        // A timed-out physical capture remains admitted. Cleanup is a diagnostic limit,
        // not a relaxed response budget or early permit release.
        for _ in 0..<1_200 where !(await completion.isFinished) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await completion.isFinished)
        for _ in 0..<100 where coordinator.unfinishedCount != 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.unfinishedCount == 0)
        await MainActor.run { withExtendedLifetime(fixture) {} }
    }

    @Test @MainActor func mixedFixtureWaitsForProtectedWriteAndPreservesSavedReceipt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let handler = env.handler
        let coordinator = MCPReadCoordinator()
        let key = "portfolio-foundation-mixed-write"
        let started = ContinuousClock.now
        let bytes = try await MCPPortfolioFoundationHarness.route {
            let read = await coordinator.execute(timeout: MCPPortfolioFoundationHarness.timeout,
                                                busy: MCPPortfolioFoundationHarness.busy) { _ in
                MCPPortfolioFoundationHarness.result(Data("{\"read\":\"complete\"}".utf8))
            }
            // Synthetic mixed adapter waits for a protected write, never wraps the
            // combined response in a read-only deadline or rewrites its saved result.
            let write = await Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                let response = await handler.handle(MCPTestHelpers.toolCallRequest(
                    tool: "create_project", arguments: ["name": "Mixed saved", "colorHex": "#112233",
                                                       "idempotencyKey": key]))
                return (try? JSONEncoder().encode(response)) ?? Data()
            }.value
            let batch = MCPReadBatchEncoding.array([read, write]) ?? Data()
            return Response(status: .ok, body: .init(byteBuffer: ByteBuffer(data: batch)))
        }
        #expect(started.duration(to: .now) >= .seconds(6))
        let frames = try #require(try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]])
        #expect(frames.first?["read"] as? String == "complete")
        let receipt = try #require(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first { $0.key == key })
        #expect(receipt.stateRawValue == "committed")
        let content = try #require((frames.last?["result"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == receipt.resultJSON)
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func blockedMainActorCannotDelayRouterTimeoutOrPublishLate() async throws {
        let coordinator = MCPReadCoordinator()
        let publication = PortfolioFoundationPublication(domain: coordinator.domain)
        let started = DispatchSemaphore(value: 0)
        let blockerFinished = NIOLockedValueBox(false)
        let blocker = Task { @MainActor in
            defer { blockerFinished.withLockedValue { $0 = true } }
            guard !Task.isCancelled else { return }
            Self.blockMainActor(started)
        }
        let didStart = Self.waitForStart(started)
        if !didStart {
            blocker.cancel()
            let drainDeadline = ContinuousClock.now + .seconds(8)
            while !blockerFinished.withLockedValue({ $0 }) && .now < drainDeadline {
                // Cleanup remains bounded even when the test task is cancelled.
                await Task.detached { try? await Task.sleep(for: .milliseconds(10)) }.value
            }
            #expect(blockerFinished.withLockedValue { $0 }, "Cancelled MainActor blocker failed to drain")
            try #require(didStart, "MainActor blocker did not start within 2 seconds; no read was admitted")
        }
        let start = ContinuousClock.now
        let bytes = try await MCPPortfolioFoundationHarness.route {
            await MCPReadTransportAdapter.response(coordinator: coordinator,
                timeout: MCPPortfolioFoundationHarness.timeout, busy: MCPPortfolioFoundationHarness.busy) { _ in
                await MainActor.run {
                    MCPPortfolioFoundationHarness.result(Data("{\"snapshotId\":\"late\"}".utf8),
                                                        publications: [publication])
                }
            }
        }
        let elapsed = start.duration(to: .now)
        print("PORTFOLIO_BLOCKED router_and_body_elapsed=\(elapsed) blocked_main_actor=6s")
        #expect(bytes == MCPPortfolioFoundationHarness.timeout)
        #expect(elapsed <= .seconds(5))
        #expect(coordinator.unfinishedCount == 1)
        await blocker.value
        for _ in 0..<100 where coordinator.unfinishedCount != 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(publication.counts == [false, true])
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func wholeReadOnlyRouterBatchBoundsSlowEncodingAndDiscardsReadyPublication() async throws {
        let coordinator = MCPReadCoordinator()
        let publication = PortfolioFoundationPublication(domain: coordinator.domain)
        let work = MCPReadBatchWork(timeout: MCPPortfolioFoundationHarness.timeout,
                                   busy: MCPPortfolioFoundationHarness.busy, responds: true) { _ in
            MCPPortfolioFoundationHarness.result(Data("{\"snapshotId\":\"private\"}".utf8),
                                                publications: [publication])
        }
        let start = ContinuousClock.now
        let bytes = try await MCPPortfolioFoundationHarness.route {
            let result = await coordinator.executeBatch([.read(work)]) { values in
                Self.slowEncode()
                return MCPPortfolioFoundationHarness.result(
                    MCPReadBatchEncoding.array(values.map { $0?.encodedResponse }) ?? Data(),
                    publications: values.compactMap { $0 }.flatMap(\.publications))
            }
            return Response(status: .ok, body: .init(byteBuffer: ByteBuffer(data: result ?? Data())))
        }
        let elapsed = start.duration(to: .now)
        print("PORTFOLIO_BATCH router_and_body_elapsed=\(elapsed) slow_encode=6s")
        #expect(elapsed <= .seconds(5))
        #expect(bytes == Data("[{\"error\":\"READ_TIMEOUT\"}]".utf8))
        #expect(coordinator.unfinishedCount == 1)
        for _ in 0..<150 where coordinator.unfinishedCount != 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.unfinishedCount == 0)
        #expect(publication.counts == [false, true])
    }

    @Test @concurrent func routerBodyFailurePreservesErrorAndAwaitsChannelCleanup() async throws {
        let started = ContinuousClock.now
        do {
            _ = try await MCPPortfolioFoundationHarness.route {
                Response(status: .ok, body: .init { writer in
                    try await writer.write(ByteBuffer(string: "partial fixture body"))
                    throw FoundationBodyFailure.intentional
                })
            }
            Issue.record("Throwing response body unexpectedly succeeded")
        } catch let error as FoundationBodyFailure {
            #expect(error == .intentional)
        }
        #expect(started.duration(to: .now) <= .seconds(5))
        let bytes = try await MCPPortfolioFoundationHarness.route {
            Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: "next clean response")))
        }
        #expect(bytes == Data("next clean response".utf8))
    }

    private enum FoundationBodyFailure: Error, Equatable { case intentional }

    @MainActor private static func blockMainActor(_ signal: DispatchSemaphore) {
        signal.signal()
        Thread.sleep(forTimeInterval: 6)
    }

    private static func waitForStart(_ signal: DispatchSemaphore) -> Bool {
        signal.wait(timeout: .now() + .seconds(2)) == .success
    }
    private static func slowEncode() { Thread.sleep(forTimeInterval: 6) }
}
#endif
