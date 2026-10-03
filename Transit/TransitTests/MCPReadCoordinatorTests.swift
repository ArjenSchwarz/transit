#if os(macOS)
import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIOCore
import NIOEmbedded
import Testing
@testable import Transit

@Suite(.serialized)
nonisolated struct MCPReadCoordinatorTests {
    @Test @concurrent func actualRouterReturnsTimeoutWhileMainActorIsBlocked() async throws {
        let coordinator = MCPReadCoordinator()
        let started = DispatchSemaphore(value: 0)
        let blocker = Task { @MainActor in
            started.signal()
            Thread.sleep(forTimeInterval: 6)
        }
        Self.waitForStart(started)
        let router = Router(context: MCPRequestContext.self)
        router.post("/read") { _, _ in
            await MCPReadTransportAdapter.response(coordinator: coordinator,
                timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
                    await MainActor.run { Self.result("success") }
                }
        }
        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = MCPRequestContext(source: ApplicationRequestContextSource(
            channel: channel, logger: Logger(label: "read-deadline-fixture")))
        let request = Request(head: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/read"),
                              body: RequestBody(buffer: ByteBuffer()))
        let start = ContinuousClock.now
        let response = try await router.buildResponder().respond(to: request, context: context)
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .seconds(5))
        #expect(response.status == .ok)
        #expect(coordinator.unfinishedCount == 1)
        await blocker.value
        try await Task.sleep(for: .milliseconds(30))
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func timeoutAndRestartNeverReleasePhysicalPermits() async throws {
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(40))
        let latch = ReadWorkerLatch()
        let calls = (0..<8).map { _ in Task {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
                await latch.wait()
                return Self.result("late")
            }
        } }
        for call in calls { #expect(await call.value == Data("timeout".utf8)) }
        #expect(coordinator.unfinishedCount == 8)
        coordinator.stop()
        coordinator.start()
        let ninth = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
            Issue.record("busy request launched a worker")
            return Self.result("unexpected")
        }
        #expect(ninth == Data("busy".utf8))
        await latch.release()
        for _ in 0..<100 where coordinator.unfinishedCount != 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(coordinator.unfinishedCount == 0)
    }

    private static func waitForStart(_ semaphore: DispatchSemaphore) { semaphore.wait() }

    private static func result(_ text: String) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data(text.utf8), publications: [],
                           publicationErrors: PreencodedPublicationErrors(
                            busy: Data("busy".utf8), expired: Data("expired".utf8), capacity: Data("capacity".utf8)))
    }
}

private actor ReadWorkerLatch {
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() {
        released = true
        let waiting = continuations
        continuations = []
        for continuation in waiting { continuation.resume() }
    }
}
#endif
