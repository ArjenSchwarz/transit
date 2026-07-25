#if os(macOS)
import Foundation

/// Transport-level `Origin` / `Host` validation for the MCP HTTP endpoint.
///
/// The MCP Streamable HTTP transport requires servers to validate the `Origin`
/// header on every incoming connection, because binding to 127.0.0.1 does not
/// keep the endpoint away from the browser running on the same machine. Without
/// this check a page on any website can `fetch()` the local endpoint, and a
/// DNS-rebinding host can make the browser treat it as same-origin.
///
/// Policy (see `rejectionReason(origin:authority:)`):
/// - `Origin` present: must be an `http`/`https` origin whose host is loopback.
/// - `Host` present: must be a loopback host. A public hostname reaching a
///   server bound to 127.0.0.1 is the DNS-rebinding signature.
/// - `Origin` absent: allowed. Real MCP clients (Claude Code, CLI callers) are
///   not browsers and send no `Origin` at all, so absence must keep working.
///
/// Parsing is deliberately strict and hand-rolled rather than delegated to
/// `URL`/`URLComponents`: those parsers are lenient by design and would, for
/// example, read the host of `http://127.0.0.1@evil.example.com` as
/// `evil.example.com`. A security check should fail closed on anything it does
/// not fully understand.
nonisolated enum MCPOriginValidator {

    /// Hosts accepted as local. Deliberately exact matches — the server only
    /// ever binds 127.0.0.1, and wildcard forms such as `*.localhost` are a
    /// known bypass on resolvers that map them to loopback.
    static let loopbackHosts: Set<String> = [
        "127.0.0.1",
        "localhost",
        "::1",
        "0:0:0:0:0:0:0:1"
    ]

    /// Why a request must be rejected, or `nil` when it may proceed.
    ///
    /// - Parameters:
    ///   - origin: The `Origin` header value, or `nil` when absent.
    ///   - authority: The `Host` header value (Hummingbird surfaces it as
    ///     `HTTPRequest.authority`), or `nil` when absent.
    static func rejectionReason(origin: String?, authority: String?) -> String? {
        if let origin, !isAllowedOrigin(origin) {
            return "Origin not allowed"
        }
        if let authority, !isLoopbackAuthority(authority) {
            return "Host not allowed"
        }
        return nil
    }

    /// Whether a serialized origin (RFC 6454, `scheme://host[:port]`) names a
    /// loopback host over HTTP or HTTPS.
    static func isAllowedOrigin(_ rawOrigin: String) -> Bool {
        let origin = rawOrigin.trimmingCharacters(in: .whitespaces)

        // `Origin: null` is what sandboxed iframes and `file://` documents send.
        // It is opaque, not local, and must never be treated as trusted.
        guard let separator = origin.range(of: "://") else { return false }

        let scheme = origin[..<separator.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return false }

        let authority = String(origin[separator.upperBound...])
        // A serialized origin carries no userinfo, path, query or fragment.
        // Anything else is either malformed or a parser-confusion attempt.
        guard !authority.isEmpty,
              !authority.contains("@"),
              !authority.contains("/"),
              !authority.contains("?"),
              !authority.contains("#") else { return false }

        return isLoopbackAuthority(authority)
    }

    /// Whether an `authority` (`host` or `host:port`, IPv6 hosts bracketed)
    /// names a loopback host.
    static func isLoopbackAuthority(_ rawAuthority: String) -> Bool {
        let authority = rawAuthority.trimmingCharacters(in: .whitespaces)
        guard !authority.isEmpty else { return false }

        let host: String
        if authority.hasPrefix("[") {
            // IPv6 literal: `[::1]` or `[::1]:3141`.
            guard let closing = authority.firstIndex(of: "]") else { return false }
            host = String(authority[authority.index(after: authority.startIndex)..<closing])
            let remainder = authority[authority.index(after: closing)...]
            guard remainder.isEmpty || isPortSuffix(String(remainder)) else { return false }
        } else if let colon = authority.lastIndex(of: ":") {
            host = String(authority[..<colon])
            guard isPortSuffix(String(authority[colon...])) else { return false }
        } else {
            host = authority
        }

        return loopbackHosts.contains(host.lowercased())
    }

    /// Whether `suffix` is a `":<port>"` fragment with a valid TCP port.
    ///
    /// The explicit ASCII-digit check is not redundant with `Int(_:)`: that
    /// initializer also accepts a leading `+`, which would otherwise let a
    /// `:+80` suffix through as port 80.
    private static func isPortSuffix(_ suffix: String) -> Bool {
        guard suffix.hasPrefix(":") else { return false }
        let digits = suffix.dropFirst()
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = Int(digits) else { return false }
        return MCPSettings.validPortRange.contains(port)
    }
}

#endif
