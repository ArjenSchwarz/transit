#if os(macOS)
import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
import Testing
@testable import Transit

@Suite(.serialized)
nonisolated struct MCPReadCoordinatorTests {
    @Test @concurrent func actualRouterReturnsTimeoutWhileMainActorIsBlocked() async throws {
        let coordinator = MCPReadCoordinator()
        let started = DispatchSemaphore(value: 0)
        let blocker = Task { @MainActor in
            Self.blockMainActor(started)
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
        let writer = ReadResponseWriter()
        try await response.body.write(writer)
        let elapsed = start.duration(to: .now)
        #expect(Data(buffer: writer.bytes.withLockedValue { $0 }) == Data("timeout".utf8))
        print("READ_DEADLINE router_and_body_elapsed=\(elapsed) blocked_main_actor=6s")
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

    @Test @concurrent func wholeBatchFallbackWinsBlockedAssemblyAndRetainsOnePermit() async throws {
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(50))
        let publication = ReadRecordingPublication(domain: coordinator.domain)
        let work = MCPReadBatchWork(timeout: Data("0".utf8), busy: Data("-1".utf8), responds: true) { _ in
            Self.result("1")
        }
        let elements = (0..<8).map { _ in MCPReadBatchElement.read(work) }
        let started = ContinuousClock.now
        let bytes = await coordinator.executeBatch(elements) { values in
            Self.blockAssembly()
            let encoded = MCPReadBatchEncoding.array(values.map { $0?.encodedResponse }) ?? Data()
            return PreparedReadResult(encodedResponse: encoded, publications: [publication],
                                      publicationErrors: Self.result("rejected").publicationErrors)
        }
        #expect(started.duration(to: .now) < .milliseconds(200))
        #expect(bytes == Data("[0,0,0,0,0,0,0,0]".utf8))
        #expect(coordinator.unfinishedCount == 1)
        try await Task.sleep(for: .milliseconds(550))
        #expect(coordinator.unfinishedCount == 0)
        #expect(publication.counts() == [0, 1])
    }

    @Test @concurrent func stoppedBeforeDispatchDoesNotLeaveAssemblyPermit() async throws {
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(20))
        let work = MCPReadBatchWork(timeout: Data("0".utf8), busy: Data("-1".utf8), responds: true) { _ in
            Issue.record("expired undispatched read started physical work")
            return Self.result("1")
        }
        let bytes = await coordinator.executeBatch([.read(work), .read(work)],
                                                   admittedAt: .now - .seconds(1)) { _ in
            Issue.record("expired batch assembled success")
            return Self.result("unexpected")
        }
        #expect(bytes == Data("[0,0]".utf8))
        try await Task.sleep(for: .milliseconds(30))
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func seededTerminalRacesNeverPublishAfterTimeoutOrStop() async throws {
        var seed: UInt64 = 63
        for _ in 0..<120 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let coordinator = MCPReadCoordinator(cutoff: .milliseconds(4))
            let publication = ReadRecordingPublication(domain: coordinator.domain)
            let delay = Int(seed % 8)
            let stop = seed & 16 != 0
            let response = Task {
                await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
                    try? await Task.sleep(for: .milliseconds(delay))
                    return PreparedReadResult(encodedResponse: Data("success".utf8), publications: [publication],
                                              publicationErrors: Self.result("busy").publicationErrors)
                }
            }
            if stop {
                try await Task.sleep(for: .milliseconds(1))
                coordinator.stop()
                coordinator.start()
            }
            let bytes = await response.value
            #expect(["success", "timeout", "busy"].contains(String(bytes: bytes, encoding: .utf8) ?? "invalid"))
            try await Task.sleep(for: .milliseconds(10))
            #expect(coordinator.unfinishedCount == 0)
            #expect(publication.counts()[0] == (bytes == Data("success".utf8) ? 1 : 0))
            #expect(publication.counts().reduce(0, +) <= 1)
        }
    }

    private static func blockAssembly() { Thread.sleep(forTimeInterval: 0.5) }

    @MainActor private static func blockMainActor(_ semaphore: DispatchSemaphore) {
        semaphore.signal()
        Thread.sleep(forTimeInterval: 6)
    }

    private static func waitForStart(_ semaphore: DispatchSemaphore) { semaphore.wait() }

    private static func result(_ text: String) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data(text.utf8), publications: [],
                           publicationErrors: PreencodedPublicationErrors(
                            busy: Data("busy".utf8), expired: Data("expired".utf8), capacity: Data("capacity".utf8)))
    }
}

private nonisolated final class ReadRecordingPublication: MCPPreparedPublication, @unchecked Sendable {
    let publicationStoreID = MCPPublicationStoreID(rawValue: UUID())
    private let domain: MCPReadPublicationDomain
    private var commits = 0
    private var discards = 0
    init(domain: MCPReadPublicationDomain) { self.domain = domain }
    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection? { nil }
    func commitLocked(in domain: MCPReadPublicationDomain) { if commits + discards == 0 { commits += 1 } }
    func discardLocked(in domain: MCPReadPublicationDomain) { if commits + discards == 0 { discards += 1 } }
    func counts() -> [Int] { domain.withLock { [commits, discards] } }
}

private nonisolated final class ReadResponseWriter: ResponseBodyWriter {
    let bytes = NIOLockedValueBox(ByteBuffer())
    func write(_ buffer: ByteBuffer) async throws { _ = bytes.withLockedValue { $0.writeImmutableBuffer(buffer) } }
    func finish(_: HTTPFields?) async throws {}
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
