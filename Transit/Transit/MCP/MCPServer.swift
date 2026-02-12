#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat

@MainActor @Observable
final class MCPServer {

    private let toolHandler: MCPToolHandler
    private var serverTask: Task<Void, Never>?

    private(set) var isRunning = false

    init(toolHandler: MCPToolHandler) {
        self.toolHandler = toolHandler
    }

    func start(port: Int) {
        guard !isRunning else { return }
        isRunning = true

        let handler = toolHandler
        let setNotRunning = { @MainActor [weak self] in
            self?.isRunning = false
        }
        serverTask = Task.detached {
            let router = Router()
            router.post("mcp") { request, _ -> Response in
                let body = try await request.body.collect(upTo: 1_048_576)
                let data = Data(buffer: body)

                guard let rpcRequest = try? JSONDecoder().decode(
                    JSONRPCRequest.self, from: data
                ) else {
                    let err = JSONRPCResponse.error(
                        id: nil,
                        code: JSONRPCErrorCode.parseError,
                        message: "Invalid JSON"
                    )
                    return Self.jsonResponse(err)
                }

                let rpcResponse = await handler.handle(rpcRequest)
                return Self.jsonResponse(rpcResponse)
            }

            let app = Application(
                router: router,
                configuration: .init(
                    address: .hostname("127.0.0.1", port: port)
                )
            )

            do {
                try await app.runService()
            } catch {
                // Server stopped or failed to bind
            }
            await setNotRunning()
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        isRunning = false
    }

    // MARK: - Helpers

    nonisolated private static func jsonResponse(
        _ response: JSONRPCResponse
    ) -> Response {
        let data: Data
        do {
            data = try JSONEncoder().encode(response)
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
