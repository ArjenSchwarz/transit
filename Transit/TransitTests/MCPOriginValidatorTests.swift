#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Unit tests for T-1833: the parsing and policy rules behind the MCP
/// endpoint's `Origin` / `Host` validation.
///
/// The route-level behaviour is covered by `MCPServerOriginValidationTests`;
/// these tests pin down the edge cases of the parser itself, which is
/// hand-rolled precisely because `URL`/`URLComponents` are too lenient for a
/// security check.
@MainActor
struct MCPOriginValidatorTests {

    // MARK: - Allowed origins

    @Test func loopbackOriginsAreAllowed() {
        #expect(MCPOriginValidator.isAllowedOrigin("http://127.0.0.1:3141"))
        #expect(MCPOriginValidator.isAllowedOrigin("http://localhost:3141"))
        #expect(MCPOriginValidator.isAllowedOrigin("https://localhost"))
        #expect(MCPOriginValidator.isAllowedOrigin("http://[::1]:3141"))
        #expect(MCPOriginValidator.isAllowedOrigin("http://127.0.0.1"))
    }

    @Test func schemeAndHostComparisonIsCaseInsensitive() {
        #expect(MCPOriginValidator.isAllowedOrigin("HTTP://LOCALHOST:3141"))
    }

    @Test func surroundingWhitespaceIsTolerated() {
        #expect(MCPOriginValidator.isAllowedOrigin("  http://127.0.0.1:3141  "))
    }

    // MARK: - Rejected origins

    @Test func foreignOriginsAreRejected() {
        #expect(!MCPOriginValidator.isAllowedOrigin("https://evil.example.com"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://attacker.test:3141"))
    }

    @Test func opaqueNullOriginIsRejected() {
        #expect(!MCPOriginValidator.isAllowedOrigin("null"))
    }

    @Test func nonHTTPSchemesAreRejected() {
        #expect(!MCPOriginValidator.isAllowedOrigin("file://localhost"))
        #expect(!MCPOriginValidator.isAllowedOrigin("ws://127.0.0.1:3141"))
        #expect(!MCPOriginValidator.isAllowedOrigin("chrome-extension://abcdef"))
    }

    @Test func userInfoConfusionIsRejected() {
        // A lenient parser resolves the host of this to evil.example.com.
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1@evil.example.com"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://localhost@evil.example.com"))
    }

    @Test func suffixAndSubdomainLookalikesAreRejected() {
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1.evil.com"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://notlocalhost"))
        // `*.localhost` resolves to loopback on some resolvers; exact match only.
        #expect(!MCPOriginValidator.isAllowedOrigin("http://evil.localhost"))
    }

    @Test func pathQueryOrFragmentMakesOriginInvalid() {
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1:3141/mcp"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1:3141?x=1"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1:3141#f"))
    }

    @Test func malformedOriginsAreRejected() {
        #expect(!MCPOriginValidator.isAllowedOrigin(""))
        #expect(!MCPOriginValidator.isAllowedOrigin("127.0.0.1:3141"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1:notaport"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://127.0.0.1:99999"))
        #expect(!MCPOriginValidator.isAllowedOrigin("http://[::1"))
    }

    // MARK: - Authority (Host header) rules

    @Test func loopbackAuthoritiesAreAllowed() {
        #expect(MCPOriginValidator.isLoopbackAuthority("127.0.0.1:3141"))
        #expect(MCPOriginValidator.isLoopbackAuthority("127.0.0.1"))
        #expect(MCPOriginValidator.isLoopbackAuthority("localhost:3141"))
        #expect(MCPOriginValidator.isLoopbackAuthority("[::1]:3141"))
        #expect(MCPOriginValidator.isLoopbackAuthority("[::1]"))
    }

    @Test func rebindingAuthoritiesAreRejected() {
        #expect(!MCPOriginValidator.isLoopbackAuthority("rebind.example.com:3141"))
        #expect(!MCPOriginValidator.isLoopbackAuthority("evil.localhost:3141"))
        #expect(!MCPOriginValidator.isLoopbackAuthority(""))
    }

    // MARK: - Combined policy

    @Test func absentOriginAndAbsentHostAreAllowed() {
        // A non-browser MCP client sends neither header value we care about.
        #expect(MCPOriginValidator.rejectionReason(origin: nil, authority: nil) == nil)
    }

    @Test func absentOriginWithLoopbackHostIsAllowed() {
        #expect(MCPOriginValidator.rejectionReason(origin: nil, authority: "127.0.0.1:3141") == nil)
    }

    @Test func loopbackOriginWithLoopbackHostIsAllowed() {
        let reason = MCPOriginValidator.rejectionReason(
            origin: "http://localhost:3141", authority: "localhost:3141"
        )
        #expect(reason == nil)
    }

    @Test func foreignOriginIsRejectedEvenWithLoopbackHost() {
        let reason = MCPOriginValidator.rejectionReason(
            origin: "https://evil.example.com", authority: "127.0.0.1:3141"
        )
        #expect(reason != nil)
    }

    @Test func rebindingHostIsRejectedWhenOriginAbsent() {
        let reason = MCPOriginValidator.rejectionReason(
            origin: nil, authority: "rebind.example.com:3141"
        )
        #expect(reason != nil)
    }
}

#endif
