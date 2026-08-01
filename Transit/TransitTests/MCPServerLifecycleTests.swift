#if os(macOS)
import Darwin
import Foundation
import Logging
import ServiceLifecycle
import Testing
@testable import Transit

/// Regression tests for T-1826: listener lifecycle changes must serialize
/// explicit graceful shutdown before another Hummingbird application binds.
///
/// The original implementation discarded a cancelled task immediately. The
/// first reviewed fix awaited that task, but Swift Service Lifecycle handles
/// task cancellation by cancelling children rather than invoking Hummingbird's
/// listener-closing graceful-shutdown path. Both versions could race a rebind.
@MainActor @Suite(.serialized)
struct MCPServerLifecycleTests {

    @Test func stopReturnsOnlyAfterListenerReleasesPort() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        await server.start(port: port)
        try #require(await waitUntilListening(port: port), "Initial listener did not start")

        // Awaiting stop must mean teardown is complete, not merely requested.
        // The pre-fix synchronous stop returns before Hummingbird closes the
        // listener, so this immediate same-port bind fails with EADDRINUSE.
        await server.stop()

        let bindError = bindLoopbackPort(port)
        #expect(bindError == nil, "Listener still owns port after stop returned (errno \(bindError ?? 0))")
    }

    @Test(arguments: 1...20)
    func samePortRestartWaitsForOldListenerTeardown(repetition: Int) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        await server.start(port: port)
        try #require(
            await waitUntilListening(port: port),
            "Initial listener did not start in repetition \(repetition)"
        )

        await server.restart(port: port)

        #expect(
            await waitUntilListening(port: port),
            "Same-port restart repetition \(repetition) raced listener shutdown: \(server.startError ?? "no error")"
        )
        #expect(server.startError == nil)
        await server.stop()
    }

    @Test func differentPortRestartReleasesOldListenerBeforeBindingNewOne() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let oldPort = try availableLoopbackPort()
        var newPort = try availableLoopbackPort()
        while newPort == oldPort {
            newPort = try availableLoopbackPort()
        }

        await server.start(port: oldPort)
        try #require(await waitUntilListening(port: oldPort), "Initial listener did not start")

        await server.restart(port: newPort)

        #expect(bindLoopbackPort(oldPort) == nil, "Restart must release the old port")
        #expect(
            await waitUntilListening(port: newPort),
            "Different-port restart did not bind the replacement: \(server.startError ?? "no error")"
        )
        #expect(server.startError == nil)
        await server.stop()
    }

    @Test func rapidOffOnRequestsCoalesceWithoutAddressInUse() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        await server.start(port: port)
        try #require(await waitUntilListening(port: port), "Initial listener did not start")

        var requests: [Task<Void, Never>] = []
        for _ in 0..<8 {
            requests.append(Task { @MainActor in await server.stop() })
            requests.append(Task { @MainActor in await server.start(port: port) })
        }
        for request in requests {
            await request.value
        }
        // Make the final desired state explicit; the burst above is allowed to
        // coalesce intermediate requests, but must not leave an old bind alive.
        await server.start(port: port)

        #expect(
            await waitUntilListening(port: port),
            "Rapid off/on must converge on one running listener: \(server.startError ?? "no error")"
        )
        #expect(server.isRunning)
        #expect(server.startError == nil)
        await server.stop()
    }

    @Test func lifecycleConfigurationBoundsShutdownWithoutSignalTraps() {
        let configuration = MCPServerLifecycleConfiguration.make(
            services: [],
            logger: Logger(label: "MCPServerLifecycleTests")
        )

        #expect(
            configuration.maximumGracefulShutdownDuration
                == MCPServerLifecycleConfiguration.defaultMaximumGracefulShutdown
        )
        #expect(configuration.gracefulShutdownSignals.isEmpty)
        #expect(configuration.cancellationSignals.isEmpty)
    }

    @Test func gracefulShutdownTimeoutEscalatesToCancellation() async throws {
        let state = CancellationOnlyServiceState()
        let service = CancellationOnlyService(state: state)
        let configuration = MCPServerLifecycleConfiguration.make(
            services: [service],
            logger: Logger(label: "MCPServerLifecycleTests.timeout"),
            maximumGracefulShutdown: .milliseconds(50)
        )
        let serviceGroup = ServiceGroup(configuration: configuration)
        let runTask = Task { try await serviceGroup.run() }
        await state.waitUntilStarted()

        let clock = ContinuousClock()
        let startedAt = clock.now
        await serviceGroup.triggerGracefulShutdown()
        try await runTask.value

        #expect(clock.now - startedAt < .seconds(1))
        let cancellationObserved = await state.cancellationObserved
        #expect(cancellationObserved)
    }

    @Test func reusableBindProbeDistinguishesLiveListenerFromReleasedPort() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        await server.start(port: port)
        try #require(await waitUntilListening(port: port), "Initial listener did not start")

        #expect(
            bindLoopbackPort(port) != nil,
            "SO_REUSEADDR probe must still reject a live listener"
        )
        await server.stop()
        #expect(
            bindLoopbackPort(port) == nil,
            "SO_REUSEADDR probe must accept a released port despite readiness-probe TIME_WAIT"
        )
    }

    @Test func startOnOccupiedPortSurfacesBindFailure() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        // An unrelated listener holds the port, which is the failure the
        // asynchronous bind path must report rather than silently claim to run.
        let blocker = try occupyLoopbackPort(port)
        defer { close(blocker) }

        await server.start(port: port)

        #expect(
            await waitUntilStartFails(server),
            "A bind failure on an occupied port must surface through startError"
        )
        #expect(!server.isRunning)
        await server.stop()
    }

    @Test func invalidPortRequestReleasesRunningListener() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        await server.start(port: port)
        try #require(await waitUntilListening(port: port), "Initial listener did not start")

        // An invalid port is a desired state rather than an early return, so it
        // must tear the running listener down instead of leaving it bound.
        await server.start(port: 70000)

        #expect(!server.isRunning)
        #expect(server.startError != nil)
        #expect(
            bindLoopbackPort(port) == nil,
            "Invalid-port request must release the previous listener"
        )
    }

    private func waitUntilListening(
        port: Int,
        timeout: Duration = .seconds(3)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if canConnectToLoopbackPort(port) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitUntilStartFails(
        _ server: MCPServer,
        timeout: Duration = .seconds(3)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if server.startError != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func loopbackAddress(port: Int) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }

    private func withSocketAddress<T>(
        _ address: inout sockaddr_in,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
    ) -> T {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private func canConnectToLoopbackPort(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = loopbackAddress(port: port)
        return withSocketAddress(&address) { connect(descriptor, $0, $1) } == 0
    }

    /// Probes whether `port` is bindable again. `SO_REUSEADDR` mirrors what
    /// SwiftNIO sets on its listening socket, so a connection the readiness
    /// probe left in `TIME_WAIT` does not masquerade as "the old listener still
    /// owns the port". A live listener still rejects the bind on Darwin, which
    /// is the signal these tests rely on.
    private func bindLoopbackPort(_ port: Int) -> Int32? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return errno }
        defer { close(descriptor) }
        enableAddressReuse(descriptor)

        var address = loopbackAddress(port: port)
        return withSocketAddress(&address) { bind(descriptor, $0, $1) } == 0 ? nil : errno
    }

    /// Holds `port` with a listening socket so a Hummingbird bind must fail.
    /// The caller owns the returned descriptor and must `close` it.
    private func occupyLoopbackPort(_ port: Int) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LifecycleTestError.socketCreationFailed(errno)
        }

        var address = loopbackAddress(port: port)
        let bindResult = withSocketAddress(&address) { bind(descriptor, $0, $1) }
        guard bindResult == 0, listen(descriptor, 1) == 0 else {
            let failure = errno
            close(descriptor)
            throw LifecycleTestError.bindFailed(failure)
        }
        return descriptor
    }

    private func enableAddressReuse(_ descriptor: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }

    private func availableLoopbackPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LifecycleTestError.socketCreationFailed(errno)
        }
        defer { close(descriptor) }

        var address = loopbackAddress(port: 0)
        guard withSocketAddress(&address, { bind(descriptor, $0, $1) }) == 0 else {
            throw LifecycleTestError.bindFailed(errno)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            throw LifecycleTestError.socketNameFailed(errno)
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

private enum LifecycleTestError: Error {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case socketNameFailed(Int32)
}

private nonisolated struct CancellationOnlyService: Service {
    let state: CancellationOnlyServiceState

    func run() async throws {
        await state.markStarted()
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            await state.markCancellationObserved()
        }
    }
}

private actor CancellationOnlyServiceState {
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private(set) var cancellationObserved = false

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func markStarted() {
        started = true
        startContinuation?.resume()
        startContinuation = nil
    }

    func markCancellationObserved() {
        cancellationObserved = true
    }
}

#endif
