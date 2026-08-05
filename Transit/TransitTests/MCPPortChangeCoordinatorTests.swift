#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPPortChangeCoordinatorTests {

    @Test func committedPortQueuesOnlyTheLatestDistinctEnabledValue() {
        var state = MCPPortChangeState()

        let queuedFirst = state.enqueueCommittedPort(3142, isEnabled: true)
        let queuedDuplicate = state.enqueueCommittedPort(3142, isEnabled: true)
        let queuedLatest = state.enqueueCommittedPort(3143, isEnabled: true)

        #expect(queuedFirst)
        #expect(!queuedDuplicate)
        #expect(queuedLatest)
        #expect(state.takePendingPort() == 3143)
        #expect(state.takePendingPort() == nil)
    }

    @Test func disabledServerDoesNotQueuePortChangeOrStartLater() {
        var state = MCPPortChangeState()

        let queuedWhileDisabled = state.enqueueCommittedPort(3142, isEnabled: false)
        #expect(!queuedWhileDisabled)
        #expect(state.takePendingPort() == nil)

        let queuedWhileEnabled = state.enqueueCommittedPort(3142, isEnabled: true)
        #expect(queuedWhileEnabled)
        state.cancelPendingPort()
        #expect(state.takePendingPort() == nil)
    }

    @Test func setupCommandUsesActiveListenerPortUntilReplacementIsLive() {
        #expect(
            MCPPortChangeState.setupCommandPort(
                isEnabled: true,
                activeListenerPort: 3141
            ) == 3141
        )
        #expect(
            MCPPortChangeState.setupCommandPort(
                isEnabled: true,
                activeListenerPort: nil
            ) == nil
        )
        #expect(
            MCPPortChangeState.setupCommandPort(
                isEnabled: false,
                activeListenerPort: 3141
            ) == nil
        )
    }
}

@MainActor @Suite(.serialized)
struct MCPPortChangeLiveTests {

    @Test func focusLossPortCommitReplacesLiveListenerWithoutSubmit() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let oldPort = try MCPPortChangeLoopbackTestSupport.availablePort()
        var committedPort = try MCPPortChangeLoopbackTestSupport.availablePort()
        while committedPort == oldPort {
            committedPort = try MCPPortChangeLoopbackTestSupport.availablePort()
        }
        let coordinator = MCPPortChangeCoordinator(debounce: .seconds(60))

        await server.start(port: oldPort)
        try #require(
            await MCPPortChangeLoopbackTestSupport.waitUntilListening(port: oldPort),
            "Initial listener did not start"
        )

        // This models a numeric TextField committing when it loses focus. No
        // onSubmit/Return event is sent.
        coordinator.enqueueCommittedPort(
            committedPort,
            isEnabled: true
        ) { port in
            await server.start(port: port)
        }
        await coordinator.flushPendingPortChange()

        #expect(
            await MCPPortChangeLoopbackTestSupport.waitUntilListening(port: committedPort),
            "Focus-loss port commit did not replace the listener: \(server.startError ?? "no error")"
        )
        #expect(server.activePort == committedPort)
        #expect(
            !MCPPortChangeLoopbackTestSupport.canConnect(to: oldPort),
            "Old listener remained bound after focus-loss commit"
        )
        await server.stop()
    }
}

private enum MCPPortChangeLoopbackTestSupport {

    static func waitUntilListening(port: Int, timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if canConnect(to: port) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    static func canConnect(to port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = loopbackAddress(port: port)
        return withSocketAddress(&address) { connect(descriptor, $0, $1) } == 0
    }

    static func availablePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MCPPortChangeLoopbackTestError.socketCreationFailed(errno) }
        defer { close(descriptor) }

        var address = loopbackAddress(port: 0)
        guard withSocketAddress(&address, { bind(descriptor, $0, $1) }) == 0 else {
            throw MCPPortChangeLoopbackTestError.bindFailed(errno)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard result == 0 else { throw MCPPortChangeLoopbackTestError.socketNameFailed(errno) }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private static func loopbackAddress(port: Int) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }

    private static func withSocketAddress<T>(
        _ address: inout sockaddr_in,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
    ) -> T {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}

private enum MCPPortChangeLoopbackTestError: Error {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case socketNameFailed(Int32)
}
#endif
