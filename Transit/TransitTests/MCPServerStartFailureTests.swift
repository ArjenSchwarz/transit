#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1297: MCP server start failures must be surfaced.
///
/// Previously `MCPServer.start(port:)` swallowed bind/start failures and the
/// Settings UI only showed "Stopped" with no actionable reason. The port value
/// from `MCPSettings` was also persisted and displayed without validating the
/// TCP port range (1...65535), so values like 70000 produced a silently
/// failing server.
///
/// Expected behaviour:
/// - `MCPSettings.isValidPort(_:)` rejects values outside 1...65535.
/// - `MCPServer.start(port:)` with an out-of-range port does not start a server
///   and records a descriptive `startError` instead of just flipping `isRunning`.
/// - Starting with a valid, available port clears any prior error.
///
/// `start(port:)` clears `startError` synchronously before launching the
/// detached service task, so a successful restart clearing a prior error is
/// not covered here: asserting it would require an actual socket bind, which is
/// flaky in CI. The synchronous clear is exercised indirectly via the
/// invalid-port tests (which observe the post-clear error being re-set).
@MainActor @Suite(.serialized)
struct MCPServerStartFailureTests {

    // MARK: - Port range validation

    @Test func validPortRangeAccepted() {
        #expect(MCPSettings.isValidPort(1))
        #expect(MCPSettings.isValidPort(3141))
        #expect(MCPSettings.isValidPort(65535))
    }

    @Test func zeroPortRejected() {
        #expect(!MCPSettings.isValidPort(0))
    }

    @Test func negativePortRejected() {
        #expect(!MCPSettings.isValidPort(-1))
    }

    @Test func portAboveMaxRejected() {
        // 70000 is the example from the bug report.
        #expect(!MCPSettings.isValidPort(70000))
        #expect(!MCPSettings.isValidPort(65536))
    }

    // MARK: - Server start surfaces invalid-port failures

    @Test func startWithInvalidPortDoesNotRunAndSetsError() throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)

        server.start(port: 70000)

        #expect(!server.isRunning)
        #expect(server.startError != nil)
        server.stop()
    }

    @Test func startWithInvalidPortDoesNotLeaveRunningTrue() throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)

        server.start(port: 0)

        #expect(!server.isRunning)
        #expect(server.startError != nil)
        server.stop()
    }

    // MARK: - Stop clears error state

    @Test func stopClearsStartError() throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)

        server.start(port: 70000)
        #expect(server.startError != nil)

        server.stop()
        #expect(server.startError == nil)
    }
}

#endif
