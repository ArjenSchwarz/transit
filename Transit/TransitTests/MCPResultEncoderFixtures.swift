#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
enum MCPResultEncoderFixtures {
    static func context(_ mutation: MCPMutationRecoveryContext? = nil) -> MCPResultContext {
        MCPResultContext(tool: "fixture", semanticFailure: nil, mutationRecovery: mutation, entityPositions: [])
    }

    static func source(_ text: String, isError: Bool? = nil, origin: MCPResultOrigin = .generatedJSON,
                       evidence: MCPResultEvidence = .established) throws -> MCPResultSource {
        try MCPResultAdapter.source(text: text, isError: isError, origin: origin, evidence: evidence)
    }

    static func field(_ name: String, in value: MCPJSONValue?) -> MCPJSONValue? {
        guard case .object(let members) = value else { return nil }
        return members.first { $0.name.utf8.elementsEqual(name.utf8) }?.value
    }

    static func text(_ value: MCPJSONValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    static func result(_ bytes: Data, id: JSONRPCId) throws -> MCPJSONValue {
        let root = try MCPJSONDocument.parse(bytes).value
        #expect(field("jsonrpc", in: root) == .string("2.0"))
        switch id {
        case .string(let expected): #expect(field("id", in: root) == .string(expected))
        case .integer(let expected):
            guard case .number(let number) = field("id", in: root) else {
                Issue.record("Missing integer correlation ID")
                throw FixtureError.invalidFixture
            }
            #expect(number.lexeme == String(expected))
        }
        #expect(field("error", in: root) == nil)
        let result = try #require(field("result", in: root))
        #expect(field("resultType", in: result) == .string("complete"))
        return result
    }

    static func originalText(_ result: MCPJSONValue) throws -> String {
        guard case .array(let content) = field("content", in: result) else {
            throw FixtureError.invalidFixture
        }
        #expect(content.count == 1)
        let first = try #require(content.first)
        #expect(field("type", in: first) == .string("text"))
        return try #require(text(field("text", in: first)))
    }

    static func structured(_ result: MCPJSONValue) throws -> MCPJSONValue {
        let value = try #require(field("structuredContent", in: result))
        #expect(try field("contractVersion", in: value) == MCPJSONDocument.parse("1").value)
        return value
    }

    private static func stringEnd(_ bytes: [UInt8], _ start: Int) throws -> Int {
        var offset = start + 1
        while offset < bytes.count {
            if bytes[offset] == 92 { offset += 2; continue }
            if bytes[offset] == 34 { return offset + 1 }
            offset += 1
        }
        throw FixtureError.invalidFixture
    }

    /// Independent envelope-only parser. Never rebuilds or compares original payload numbers.
    static func rawFragment(_ data: Data, path: [String]) throws -> Data {
        try MCPJSONEnvelopeFixtureValidation.validate(data)
        let bytes = Array(data)
        func whitespace(_ offset: inout Int) {
            while offset < bytes.count, [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
        }
        func valueEnd(_ start: Int) throws -> Int {
            if bytes[start] == 34 { return try stringEnd(bytes, start) }
            if bytes[start] == 123 || bytes[start] == 91 {
                var offset = start + 1
                while offset < bytes.count {
                    whitespace(&offset)
                    if bytes[offset] == 125 || bytes[offset] == 93 { return offset + 1 }
                    if bytes[offset] == 44 || bytes[offset] == 58 { offset += 1; continue }
                    offset = try valueEnd(offset)
                }
                throw FixtureError.invalidFixture
            }
            var offset = start
            while offset < bytes.count, ![9, 10, 13, 32, 44, 125, 93].contains(bytes[offset]) { offset += 1 }
            return offset
        }
        var offset = 0
        whitespace(&offset)
        for component in path {
            guard bytes[offset] == 123 else { throw FixtureError.invalidFixture }
            offset += 1
            var found: Int?
            while offset < bytes.count {
                whitespace(&offset)
                if bytes[offset] == 125 { break }
                if bytes[offset] == 44 { offset += 1; continue }
                guard bytes[offset] == 34 else { throw FixtureError.invalidFixture }
                let end = try stringEnd(bytes, offset)
                let key = try JSONSerialization.jsonObject(with: Data(bytes[offset..<end]),
                                                           options: [.fragmentsAllowed]) as? String
                offset = end
                whitespace(&offset)
                guard bytes[offset] == 58 else { throw FixtureError.invalidFixture }
                offset += 1
                whitespace(&offset)
                if key?.utf8.elementsEqual(component.utf8) == true { found = offset; break }
                offset = try valueEnd(offset)
            }
            guard let found else { throw FixtureError.invalidFixture }
            offset = found
        }
        return Data(bytes[offset..<(try valueEnd(offset))])
    }

    static func leaves(_ value: MCPJSONValue) -> [String] {
        switch value {
        case .object(let members): return members.flatMap { [$0.name] + leaves($0.value) }
        case .array(let values): return values.flatMap(leaves)
        case .string(let text): return [text]
        case .number(let number): return [number.lexeme]
        case .boolean(let flag): return [flag ? "true" : "false"]
        case .null: return ["null"]
        }
    }

    nonisolated enum FixtureError: Error { case invalidFixture, injectedEncodingFailure, cancelled }
}

/// Test-only count is protected because checkpoints execute outside actor isolation.
nonisolated final class MCPEncoderCheckpointCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let failAt: Int?

    init(failAt: Int? = nil) { self.failAt = failAt }

    func check() throws {
        try lock.withLock {
            count += 1
            if let failAt, count >= failAt { throw MCPResultEncoderFixtures.FixtureError.cancelled }
        }
    }

    func value() -> Int { lock.withLock { count } }
}
#endif
