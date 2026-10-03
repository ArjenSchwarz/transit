#if os(macOS)
import Foundation
@testable import Transit

/// Independent fixture model: numbers are tokens, never Foundation numbers.
nonisolated indirect enum MCPJSONFixtureValue: Equatable, Sendable {
    case object([MCPJSONFixtureMember])
    case array([MCPJSONFixtureValue])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null

    func json() throws -> String {
        switch self {
        case .object(let members):
            let entries = try members.map { try Self.quote($0.name) + ":" + $0.value.json() }
            return "{" + entries.joined(separator: ",") + "}"
        case .array(let values): return "[" + (try values.map { try $0.json() }).joined(separator: ",") + "]"
        case .string(let value): return try Self.quote(value)
        case .number(let token): return token
        case .boolean(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }

    func matches(_ actual: MCPJSONValue) -> Bool {
        switch (self, actual) {
        case (.object(let expected), .object(let members)):
            return expected.count == members.count && zip(expected, members).allSatisfy {
                Array($0.name.unicodeScalars) == Array($1.name.unicodeScalars) && $0.value.matches($1.value)
            }
        case (.array(let expected), .array(let values)):
            return expected.count == values.count && zip(expected, values).allSatisfy { $0.matches($1) }
        case (.string(let expected), .string(let value)): return expected == value
        case (.number(let expected), .number(let value)): return expected == value.lexeme
        case (.boolean(let expected), .boolean(let value)): return expected == value
        case (.null, .null): return true
        default: return false
        }
    }

    /// Every candidate remains valid JSON and has less structure or simpler data.
    func shrinks() -> [MCPJSONFixtureValue] {
        switch self {
        case .object(let members) where !members.isEmpty:
            return [.object([]), .object(Array(members.dropLast())), members[0].value]
        case .array(let values) where !values.isEmpty:
            return [.array([]), .array(Array(values.dropLast())), values[0]]
        case .string(let value) where !value.isEmpty: return [.string(""), .string(String(value.prefix(1)))]
        case .number(let token) where token != "0": return [.number("0")]
        case .boolean(true): return [.boolean(false)]
        default: return []
        }
    }

    static func minimizedFailure(
        _ value: MCPJSONFixtureValue,
        fails: (MCPJSONFixtureValue) -> Bool
    ) -> MCPJSONFixtureValue {
        var current = value
        while let smaller = current.shrinks().first(where: { $0 != current && fails($0) }) {
            current = smaller
        }
        return current
    }

    private static func quote(_ value: String) throws -> String {
        guard let result = String(data: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return result
    }
}

nonisolated struct MCPJSONFixtureMember: Equatable, Sendable {
    let name: String
    let value: MCPJSONFixtureValue
}

nonisolated struct MCPJSONFixtureGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func value(depth: Int = 3) -> MCPJSONFixtureValue {
        let selection = next() % (depth > 0 ? 6 : 4)
        switch selection {
        case 0: return .null
        case 1: return .boolean(next() % 2 == 0)
        case 2:
            let tokens = ["0", "-0", "9007199254740993", "18446744073709551616", "-9223372036854775809",
                          "1.00000000000000000001", "-2.300e+400", "1E-9999"]
            return .number(tokens[Int(next() % UInt64(tokens.count))])
        case 3:
            let strings = ["", "hello", "東京🛰️", "quote\"\\\n\t\u{0000}", "e\u{0301}", "/~"]
            return .string(strings[Int(next() % UInt64(strings.count))])
        case 4:
            let count = Int(next() % 4)
            return .array((0..<count).map { _ in value(depth: depth - 1) })
        default:
            let count = Int(next() % 4)
            let names = ["source", "presentation", "unknown/~\"", "contractVersion"]
            return .object((0..<count).map {
                MCPJSONFixtureMember(name: names[$0], value: value(depth: depth - 1))
            })
        }
    }

    private mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 32
    }
}
#endif
