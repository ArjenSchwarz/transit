#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOFoundationCompat

extension MCPServer {
    nonisolated static func toolListChangeStreamResponse(
        request: Request,
        context: MCPRequestContext,
        handler: MCPToolHandler
    ) async -> Response {
        guard acceptsEventStream(request.head.headerFields[.accept]) else {
            return Response(status: .methodNotAllowed, headers: [.allow: "POST"])
        }
        guard let sessionID = request.head.headerFields[.mcpSessionID] else {
            return Response(status: .badRequest)
        }
        guard let notifications = await handler.toolListChangeNotifications(
            sessionID: sessionID,
            channelClose: context.channel.closeFuture
        ) else {
            return Response(status: .notFound)
        }

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache"
            ],
            body: ResponseBody { writer in
                for await notification in notifications {
                    try await writer.write(try Self.serverSentEvent(notification))
                }
                try await writer.finish(nil)
            }
        )
    }

    /// GET listening streams require an explicit, acceptable
    /// `text/event-stream` media range. A zero quality value means the client
    /// does not accept that representation; substring lookalikes are unrelated
    /// media types and must not negotiate SSE.
    nonisolated static func acceptsEventStream(_ accept: String?) -> Bool {
        guard let accept,
              let mediaRanges = splitHTTPValue(accept[...], separator: ",") else {
            return false
        }

        for mediaRange in mediaRanges {
            guard let components = splitHTTPValue(mediaRange, separator: ";"),
                  components.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "text/event-stream" else {
                continue
            }

            var quality = 1.0
            var sawQuality = false
            var parametersAreValid = true
            for parameter in components.dropFirst() {
                let pair = parameter.split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                guard pair.count == 2 else {
                    parametersAreValid = false
                    break
                }
                guard pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "q" else {
                    continue
                }
                guard !sawQuality,
                      let parsed = qualityValue(
                        pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                      ) else {
                    parametersAreValid = false
                    break
                }
                sawQuality = true
                quality = parsed
            }
            if parametersAreValid && quality > 0 { return true }
        }
        return false
    }

    /// Splits an HTTP list while preserving separators inside quoted strings.
    /// A malformed quoted string invalidates the field instead of accidentally
    /// turning a parameter fragment into an acceptable media range.
    nonisolated private static func splitHTTPValue(
        _ value: Substring,
        separator: Character
    ) -> [Substring]? {
        var pieces: [Substring] = []
        var start = value.startIndex
        var index = start
        var isQuoted = false
        var isEscaped = false

        while index < value.endIndex {
            let character = value[index]
            if isEscaped {
                isEscaped = false
            } else if isQuoted && character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isQuoted.toggle()
            } else if character == separator && !isQuoted {
                pieces.append(value[start..<index])
                start = value.index(after: index)
            }
            index = value.index(after: index)
        }

        guard !isQuoted, !isEscaped else { return nil }
        pieces.append(value[start...])
        return pieces
    }

    /// RFC 9110 qvalue: 0 or 1 with at most three fractional digits; only zero
    /// digits may follow 1. Rejecting extensions such as `.5` and `1e-1` keeps
    /// malformed quality values from silently enabling a listening stream.
    nonisolated private static func qualityValue(_ rawValue: String) -> Double? {
        if rawValue == "0" { return 0 }
        if rawValue == "1" { return 1 }
        guard rawValue.count >= 2,
              rawValue.count <= 5,
              rawValue[rawValue.index(after: rawValue.startIndex)] == "." else {
            return nil
        }

        let integer = rawValue.first
        let fraction = rawValue.dropFirst(2)
        guard fraction.allSatisfy(\.isNumber) else { return nil }
        if integer == "1", fraction.allSatisfy({ $0 == "0" }) {
            return 1
        }
        if integer == "0" {
            return Double(rawValue)
        }
        return nil
    }

    nonisolated private static func serverSentEvent(
        _ notification: MCPServerNotification
    ) throws -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(notification)
        var event = Data("data: ".utf8)
        event.append(payload)
        event.append(contentsOf: [0x0A, 0x0A])
        return ByteBuffer(data: event)
    }
}

extension HTTPField.Name {
    nonisolated static let mcpSessionID = HTTPField.Name("Mcp-Session-Id")!
}

#endif
