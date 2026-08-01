#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1826: listener lifecycle changes must serialize
/// cancellation and teardown before another Hummingbird application binds.
///
/// Previously `stop()` only called `cancel()` and immediately discarded the
/// service task. A same-port `start()` could then bind while the cancelled
/// listener still owned the socket, fail with `EADDRINUSE`, and leave MCP off.
@MainActor @Suite(.serialized)
struct MCPServerLifecycleTests {

    @Test func stopReturnsOnlyAfterListenerReleasesPort() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        server.start(port: port)
        try #require(await waitUntilServing(port: port), "Initial listener did not start")

        // Awaiting stop must mean teardown is complete, not merely requested.
        // The pre-fix synchronous stop returns before Hummingbird closes the
        // listener, so this immediate same-port bind fails with EADDRINUSE.
        await server.stop()

        let bindError = bindLoopbackPort(port)
        #expect(bindError == nil, "Listener still owns port after stop returned (errno \(bindError ?? 0))")
    }

    @Test func samePortRestartWaitsForOldListenerTeardown() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        server.start(port: port)
        try #require(await waitUntilServing(port: port), "Initial listener did not start")

        server.stop()
        server.start(port: port)

        #expect(
            await waitUntilServing(port: port),
            "Same-port restart must not race listener shutdown: \(server.startError ?? "no error")"
        )
        #expect(server.startError == nil)
        server.stop()
    }

    @Test func rapidOffOnRequestsCoalesceWithoutAddressInUse() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let port = try availableLoopbackPort()

        server.start(port: port)
        try #require(await waitUntilServing(port: port), "Initial listener did not start")

        for _ in 0..<8 {
            server.stop()
            server.start(port: port)
        }

        #expect(
            await waitUntilServing(port: port),
            "Rapid off/on must converge on one running listener: \(server.startError ?? "no error")"
        )
        #expect(server.isRunning)
        #expect(server.startError == nil)
        server.stop()
    }

    private func waitUntilServing(
        port: Int,
        timeout: Duration = .seconds(3)
    ) async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            do {
                let (_, response) = try await session.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    return true
                }
            } catch {
                // Connection refusal is expected while a lifecycle operation
                // is still stopping or starting the loopback listener.
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
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
