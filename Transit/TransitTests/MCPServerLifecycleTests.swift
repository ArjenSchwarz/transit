#if os(macOS)
import Darwin
import Foundation
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

    private func canConnectToLoopbackPort(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func bindLoopbackPort(_ port: Int) -> Int32? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return errno }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0 ? nil : errno
    }

    private func availableLoopbackPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LifecycleTestError.socketCreationFailed(errno)
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
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

#endif
