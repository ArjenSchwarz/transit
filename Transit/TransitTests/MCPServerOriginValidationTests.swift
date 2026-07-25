#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOHTTPTypesHTTP1
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1833: the MCP Streamable HTTP endpoint must validate
/// the `Origin` header before decoding or dispatching any JSON-RPC.
///
/// The server binds to 127.0.0.1, but binding alone does not stop a malicious
/// web page (or a DNS-rebinding host) from POSTing to it from the user's own
/// browser. The MCP transport specification requires servers to validate
/// `Origin` on all incoming connections for exactly this reason:
/// https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#security-warning
///
/// Expected behaviour:
/// - A present `Origin` that is not an explicit loopback origin is rejected
///   with HTTP 403 before the body is read or dispatched.
/// - A non-loopback `Host` (the DNS-rebinding signature) is rejected too.
/// - Local MCP clients, which send no browser `Origin` header at all, keep
///   working exactly as before.
@MainActor @Suite(.serialized)
struct MCPServerOriginValidationTests {

    // MARK: - Rejected origins

    @Test func attackerOriginIsRejected() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler,
            origin: "https://evil.example.com",
            body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func attackerOriginIsRejectedBeforeDispatch() async throws {
        let env = try MCPTestHelpers.makeEnv()
        MCPTestHelpers.makeProject(in: env.context, name: "Transit")

        let status = try await respond(
            handler: env.handler,
            origin: "https://evil.example.com",
            body: Self.createTaskBody
        )

        #expect(status == .forbidden)
        // The state-changing tool must never have run.
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty)
    }

    @Test func httpAttackerOriginIsRejected() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "http://attacker.test", body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func nullOriginIsRejected() async throws {
        // Sandboxed iframes and `file://` documents send `Origin: null`.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "null", body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func localhostLookalikeOriginIsRejected() async throws {
        // `127.0.0.1.evil.com` resolves to the attacker; the prefix is bait.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "http://127.0.0.1.evil.com", body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func userInfoOriginIsRejected() async throws {
        // A permissive URL parser reads the host of
        // `http://127.0.0.1@evil.example.com` as evil.example.com.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler,
            origin: "http://127.0.0.1@evil.example.com",
            body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func nonLoopbackHostIsRejectedWhenOriginAbsent() async throws {
        // The DNS-rebinding signature: no browser Origin, but the Host header
        // names a public domain that resolves to 127.0.0.1.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler,
            origin: nil,
            host: "rebind.example.com:3141",
            body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    // MARK: - Accepted requests

    @Test func absentOriginIsAccepted() async throws {
        // Local MCP clients (CLI/agent) send no Origin header at all.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: nil, body: Self.toolsListBody
        )
        #expect(status == .ok)
    }

    @Test func absentOriginStillDispatchesStateChangingTools() async throws {
        let env = try MCPTestHelpers.makeEnv()
        MCPTestHelpers.makeProject(in: env.context, name: "Transit")

        let status = try await respond(
            handler: env.handler, origin: nil, body: Self.createTaskBody
        )

        #expect(status == .ok)
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.name == "Origin test task")
    }

    @Test func loopbackIPOriginIsAccepted() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "http://127.0.0.1:3141", body: Self.toolsListBody
        )
        #expect(status == .ok)
    }

    @Test func localhostOriginIsAccepted() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "http://localhost:3141", body: Self.toolsListBody
        )
        #expect(status == .ok)
    }

    @Test func ipv6LoopbackOriginIsAccepted() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "http://[::1]:3141", body: Self.toolsListBody
        )
        #expect(status == .ok)
    }

    // MARK: - Rejection precedes parsing

    @Test func attackerOriginIsRejectedEvenWithMalformedBody() async throws {
        // Origin validation runs before decoding, so a bad body still yields
        // 403 rather than a JSON-RPC parse error.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respond(
            handler: env.handler, origin: "https://evil.example.com", body: "{not json"
        )
        #expect(status == .forbidden)
    }

    // MARK: - Real HTTP/1.1 header mapping
    //
    // The checks above synthesise `HTTPRequest` directly. These drive the same
    // conversion Hummingbird uses in production — `HTTP1ToHTTPServerCodec`
    // calls `HTTPRequest(head, secure:splitCookie:)` — so the load-bearing
    // assumption that a raw `Host:` header lands in `head.authority` (and a raw
    // `Origin:` header in `head.headerFields`) is proven, not assumed.

    @Test func rawHTTP1RebindingHostIsRejected() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respondToRawHTTP1(
            handler: env.handler,
            headers: [("Host", "rebind.example.com:3141"), ("Content-Type", "application/json")],
            body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func rawHTTP1AttackerOriginIsRejected() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respondToRawHTTP1(
            handler: env.handler,
            headers: [
                ("Host", "127.0.0.1:3141"),
                ("Origin", "https://evil.example.com"),
                ("Content-Type", "application/json")
            ],
            body: Self.toolsListBody
        )
        #expect(status == .forbidden)
    }

    @Test func rawHTTP1LocalClientIsAccepted() async throws {
        // What `curl -X POST http://127.0.0.1:3141/mcp` actually sends.
        let env = try MCPTestHelpers.makeEnv()
        let status = try await respondToRawHTTP1(
            handler: env.handler,
            headers: [("Host", "127.0.0.1:3141"), ("Content-Type", "application/json")],
            body: Self.toolsListBody
        )
        #expect(status == .ok)
    }

    // MARK: - Helpers

    private static let toolsListBody = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#

    private static let createTaskBody = """
    {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_task",\
    "arguments":{"project":"Transit","name":"Origin test task","type":"bug"}}}
    """

    private func respond(
        handler: MCPToolHandler,
        origin: String?,
        host: String? = "127.0.0.1:3141",
        body: String
    ) async throws -> HTTPResponse.Status {
        let responder = MCPServer.makeRouter(handler: handler).buildResponder()

        var headerFields = HTTPFields()
        headerFields[.contentType] = "application/json"
        if let origin {
            headerFields[.origin] = origin
        }
        let head = HTTPRequest(
            method: .post,
            scheme: "http",
            authority: host,
            path: "/mcp",
            headerFields: headerFields
        )
        return try await dispatch(responder: responder, head: head, body: body)
    }

    /// Builds an `HTTPRequestHead` exactly as NIO's HTTP/1 decoder would, then
    /// converts it with the same initializer Hummingbird's
    /// `HTTP1ToHTTPServerCodec` uses, so the raw wire headers reach the route
    /// through the production mapping.
    private func respondToRawHTTP1(
        handler: MCPToolHandler,
        headers: [(String, String)],
        body: String
    ) async throws -> HTTPResponse.Status {
        let responder = MCPServer.makeRouter(handler: handler).buildResponder()
        let http1Head = HTTPRequestHead(
            version: .http1_1,
            method: .POST,
            uri: "/mcp",
            headers: HTTPHeaders(headers)
        )
        let head = try HTTPRequest(http1Head, secure: false, splitCookie: false)
        return try await dispatch(responder: responder, head: head, body: body)
    }

    private func dispatch(
        responder: some HTTPResponder<BasicRequestContext>,
        head: HTTPRequest,
        body: String
    ) async throws -> HTTPResponse.Status {
        let request = Request(head: head, body: RequestBody(buffer: ByteBuffer(string: body)))

        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(
                channel: channel, logger: Logger(label: "mcp-origin-tests")
            )
        )

        let response = try await responder.respond(to: request, context: context)
        return response.status
    }
}

#endif
