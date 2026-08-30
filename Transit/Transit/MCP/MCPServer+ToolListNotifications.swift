#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat

extension MCPServer {
    nonisolated static func toolListChangeStreamResponse(
        request: Request,
        handler: MCPToolHandler
    ) async -> Response {
        guard request.head.headerFields[.accept]?
            .lowercased()
            .contains("text/event-stream") == true else {
            return Response(status: .methodNotAllowed, headers: [.allow: "POST"])
        }

        let notifications = await handler.toolListChangeNotifications()
        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache"
            ],
            body: ResponseBody { writer in
                for await notification in notifications {
                    try await writer.write(Self.serverSentEvent(notification))
                }
                try await writer.finish(nil)
            }
        )
    }

    nonisolated private static func serverSentEvent(
        _ notification: MCPServerNotification
    ) -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let payload = try? encoder.encode(notification) else {
            return ByteBuffer(
                string: "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n"
            )
        }
        var event = Data("data: ".utf8)
        event.append(payload)
        event.append(contentsOf: [0x0A, 0x0A])
        return ByteBuffer(data: event)
    }
}

#endif
