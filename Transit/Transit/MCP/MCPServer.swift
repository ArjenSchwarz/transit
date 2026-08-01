#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat

@MainActor @Observable
final class MCPServer {

    private enum DesiredState: Equatable {
        case stopped
        case invalidPort(Int)
        case running(port: Int, runID: Int)
    }

    private let toolHandler: MCPToolHandler
    private var desiredState: DesiredState = .stopped
    private var lifecycleTask: Task<Void, Never>?
    private var serverTask: Task<Void, Never>?
    private var activePort: Int?
    private var activeRunID: Int?
    private var nextRunID = 0
    private var serverGeneration = 0

    private(set) var isRunning = false

    /// A human-readable reason the server is not running, or `nil` when the
    /// server is running or was stopped intentionally. Set when the configured
    /// port is invalid or when binding the listening socket fails (e.g. the
    /// port is already in use), so Settings can surface an actionable message
    /// instead of a bare "Stopped".
    private(set) var startError: String?

    init(toolHandler: MCPToolHandler) {
        self.toolHandler = toolHandler
    }
}

extension MCPServer {
    /// Starts the server unless the same port is already active or requested.
    /// Repeated requests join one reconciliation pass instead of launching
    /// competing Hummingbird applications.
    func start(port: Int) async {
        await request(runningState(port: port, forceRestart: false))
    }

    /// Replaces the current listener even when the port is unchanged. The old
    /// service task is cancelled and awaited before the replacement can bind.
    func restart(port: Int) async {
        await request(runningState(port: port, forceRestart: true))
    }

    /// Stops the server and returns only after Hummingbird has released its
    /// listener. A newer request can supersede this one while teardown awaits.
    func stop() async {
        await request(.stopped)
    }

    private func runningState(port: Int, forceRestart: Bool) -> DesiredState {
        guard MCPSettings.isValidPort(port) else {
            return .invalidPort(port)
        }

        if !forceRestart {
            if case .running(let requestedPort, let runID) = desiredState,
               requestedPort == port {
                return .running(port: port, runID: runID)
            }
            if activePort == port, let activeRunID, serverTask != nil {
                return .running(port: port, runID: activeRunID)
            }
        }

        nextRunID += 1
        return .running(port: port, runID: nextRunID)
    }

    private func request(_ state: DesiredState) async {
        desiredState = state
        if lifecycleTask == nil {
            lifecycleTask = Task { @MainActor [weak self] in
                await self?.reconcileLifecycle()
            }
        }
        let currentLifecycleTask = lifecycleTask
        await currentLifecycleTask?.value
    }

    /// Applies only the latest requested state. Requests arriving while old
    /// listener teardown is suspended overwrite stale intermediate states and
    /// are picked up by the next loop iteration.
    private func reconcileLifecycle() async {
        while true {
            let target = desiredState
            switch target {
            case .stopped:
                await tearDownCurrentServer()
                if desiredState == target {
                    startError = nil
                }

            case .invalidPort(let port):
                await tearDownCurrentServer()
                if desiredState == target {
                    startError = "Port \(port) is invalid. Use a value between "
                        + "\(MCPSettings.validPortRange.lowerBound) and "
                        + "\(MCPSettings.validPortRange.upperBound)."
                }

            case .running(let port, let runID):
                if activePort != port || activeRunID != runID || serverTask == nil {
                    await tearDownCurrentServer()
                    if desiredState == target {
                        launchServer(port: port, runID: runID)
                    }
                }
            }

            guard desiredState == target else { continue }
            lifecycleTask = nil
            return
        }
    }

    private func tearDownCurrentServer() async {
        guard let currentServerTask = serverTask else {
            activePort = nil
            activeRunID = nil
            isRunning = false
            return
        }

        // Invalidate the completion callback before cancellation. Awaiting the
        // task is the resource fence: runService does not return until its
        // graceful-shutdown handler has released the listening channel.
        serverGeneration += 1
        serverTask = nil
        activePort = nil
        activeRunID = nil
        isRunning = false
        currentServerTask.cancel()
        await currentServerTask.value
    }

    private func launchServer(port: Int, runID: Int) {
        serverGeneration += 1
        let currentGeneration = serverGeneration
        activePort = port
        activeRunID = runID
        isRunning = true
        startError = nil

        let handler = toolHandler
        let setNotRunning = { @MainActor [weak self] (failure: String?) in
            guard let self, self.serverGeneration == currentGeneration else { return }
            self.serverTask = nil
            self.activePort = nil
            self.activeRunID = nil
            self.isRunning = false
            if let failure {
                self.startError = failure
            }
        }
        serverTask = Task.detached {
            let app = Application(
                router: Self.makeRouter(handler: handler),
                configuration: .init(
                    address: .hostname("127.0.0.1", port: port)
                )
            )

            // A bind failure surfaces here (e.g. the port is already in use).
            // CancellationError is expected when serialized teardown cancels
            // and then awaits this task.
            var failure: String?
            do {
                try await app.runService()
            } catch is CancellationError {
                failure = nil
            } catch {
                failure = "Could not start server on port \(port): "
                    + error.localizedDescription
            }
            await setNotRunning(failure)
        }
    }
}

extension MCPServer {

    /// Builds the Hummingbird router for the single `POST /mcp` endpoint.
    /// `nonisolated` because under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
    /// `MCPServer` is `@MainActor` by default, but this is called from the
    /// detached (non-main-actor) task in `start(port:)`.
    nonisolated static func makeRouter(handler: MCPToolHandler) -> Router<BasicRequestContext> {
        let router = Router()
        router.post("mcp") { request, _ -> Response in
            // DNS-rebinding defence required by the MCP Streamable HTTP
            // transport. This must stay the first statement in the route: an
            // untrusted caller's body is never read, decoded, or dispatched.
            if MCPOriginValidator.rejectionReason(
                origin: request.head.headerFields[.origin],
                authority: request.head.authority
            ) != nil {
                return forbiddenResponse()
            }

            let body = try await request.body.collect(upTo: 1_048_576)
            let data = Data(buffer: body)

            switch decodeIncomingRequest(data) {
            case .success(let rpcRequest):
                // A single notification has no JSON-RPC response body.
                guard let rpcResponse = await handler.handle(rpcRequest) else {
                    return Response(status: .accepted)
                }
                return jsonResponse(rpcResponse)

            case .batch(let elements):
                return await batchResponse(for: elements, handler: handler)

            case .failure(let errorResponse):
                return jsonResponse(errorResponse)
            }
        }
        return router
    }

    /// Dispatches one non-empty JSON-RPC batch and builds its HTTP response.
    private static func batchResponse(
        for elements: [BatchElement],
        handler: MCPToolHandler
    ) async -> Response {
        var responses: [JSONRPCResponse] = []
        responses.reserveCapacity(elements.count)

        // Sequential dispatch is intentional. JSON-RPC permits any processing
        // order, and preserving input order keeps side effects deterministic
        // for Transit's shared model context.
        for element in elements {
            switch element {
            case .invalid:
                responses.append(invalidRequestResponse())
            case .request(let rpcRequest):
                // MCP 2025-03-26 lifecycle: initialize MUST NOT be in a batch.
                // Notifications still never get a response.
                if rpcRequest.method == "initialize" {
                    if !rpcRequest.isNotification {
                        responses.append(JSONRPCResponse.error(
                            id: rpcRequest.id,
                            code: JSONRPCErrorCode.invalidRequest,
                            message: "Invalid Request: initialize must not be batched"
                        ))
                    }
                } else if let rpcResponse = await handler.handle(rpcRequest) {
                    responses.append(rpcResponse)
                }
            }
        }

        // JSON-RPC forbids an empty response array. Streamable HTTP requires
        // 202 with no body when the input is notifications only.
        guard !responses.isEmpty else {
            return Response(status: .accepted)
        }
        return jsonResponse(responses)
    }

    // MARK: - Helpers

    /// Result of decoding an incoming body as one JSON-RPC request or a batch.
    nonisolated enum DecodeOutcome: Sendable {
        case success(JSONRPCRequest)
        case batch([BatchElement])
        case failure(JSONRPCResponse)
    }

    /// One member of a non-empty JSON-RPC batch. Invalid members stay in the
    /// sequence so the route can emit one -32600 response for each of them.
    nonisolated enum BatchElement: Sendable {
        case request(JSONRPCRequest)
        case invalid
    }

    /// Decode an incoming request body as a single JSON-RPC request or a
    /// non-empty JSON-RPC batch, distinguishing transport-level parse failures
    /// from protocol-level shape failures.
    ///
    /// Per JSON-RPC 2.0 §5.1 and §6:
    /// - Malformed JSON produces one `-32700 Parse error` response.
    /// - An invalid single root or an empty batch produces one `-32600 Invalid
    ///   Request` response object.
    /// - A non-empty batch preserves every member. Valid request objects are
    ///   dispatched, while each invalid member produces its own `-32600`
    ///   response in the eventual response array.
    nonisolated static func decodeIncomingRequest(
        _ data: Data
    ) -> DecodeOutcome {
        // Stage 1: confirm the bytes are well-formed JSON. `.fragmentsAllowed`
        // lets scalar roots through so they become Invalid Request rather than
        // Parse error.
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed]
            )
        } catch {
            return .failure(JSONRPCResponse.error(
                id: nil,
                code: JSONRPCErrorCode.parseError,
                message: "Parse error"
            ))
        }

        if let batch = parsed as? [Any] {
            guard !batch.isEmpty else {
                return .failure(invalidRequestResponse())
            }
            return .batch(batch.map { element in
                guard let object = element as? [String: Any],
                      let request = decodeRequestObject(object) else {
                    return .invalid
                }
                return .request(request)
            })
        }

        guard let object = parsed as? [String: Any],
              isValidRequestObjectShape(object),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            return .failure(invalidRequestResponse())
        }
        return .success(request)
    }

    /// Structural checks that `JSONRPCRequest` intentionally leaves lenient.
    /// A missing `jsonrpc` member decodes to `""` so the handler can preserve
    /// T-1106's detailed version error, but a present non-string member is not
    /// a valid Request object. Likewise, present `params` must be the structured
    /// object or array required by JSON-RPC 2.0 §4.2.
    nonisolated private static func isValidRequestObjectShape(
        _ object: [String: Any]
    ) -> Bool {
        guard object["jsonrpc"] == nil || object["jsonrpc"] is String else {
            return false
        }
        guard let params = object["params"] else {
            return true
        }
        return params is [String: Any] || params is [Any]
    }

    nonisolated private static func decodeRequestObject(
        _ object: [String: Any]
    ) -> JSONRPCRequest? {
        guard isValidRequestObjectShape(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONRPCRequest.self, from: data)
    }

    nonisolated private static func invalidRequestResponse() -> JSONRPCResponse {
        JSONRPCResponse.error(
            id: nil,
            code: JSONRPCErrorCode.invalidRequest,
            message: "Invalid Request"
        )
    }

    /// Transport-level rejection. Deliberately not a JSON-RPC error body: the
    /// request never entered a JSON-RPC session, and answering `200` with an
    /// error object would tell an attacker's page that the endpoint is live.
    ///
    /// The body is a fixed string rather than the validator's specific reason,
    /// so a probing script cannot learn whether it was the `Origin` or the
    /// `Host` check that tripped.
    nonisolated private static func forbiddenResponse() -> Response {
        Response(
            status: .forbidden,
            headers: [.contentType: "text/plain"],
            body: .init(byteBuffer: ByteBuffer(string: "Forbidden"))
        )
    }

    nonisolated private static func jsonResponse(
        _ payload: some Encodable & Sendable
    ) -> Response {
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            let fallback = """
            {"jsonrpc":"2.0","id":null,\
            "error":{"code":-32603,"message":"Encoding failed"}}
            """
            data = Data(fallback.utf8)
        }
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}

#endif
