#if os(macOS)
nonisolated struct MCPPresentationRejectionFixture: Sendable {
    let code: String
    let accepted: Bool

    static let all: [MCPPresentationRejectionFixture] = [
        .init(code: "INTERRUPTED_BEFORE_COMMIT", accepted: true),
        .init(code: "INTERNAL_ERROR", accepted: true),
        .init(code: "INTERNAL_ERROR", accepted: false)
    ]
}

#endif
