#if os(macOS)
import Foundation

/// Inspected names use decoded scalar identity, never String canonical equivalence.
nonisolated enum MCPResultInspection {
    static func member(_ name: String, in value: MCPJSONValue?,
                       checkpoint: @Sendable () throws -> Void) throws -> MCPJSONValue? {
        guard case .object(let members) = value else { return nil }
        for (index, member) in members.enumerated() {
            if index.isMultiple(of: 64) { try checkpoint() }
            if member.name.unicodeScalars.elementsEqual(name.unicodeScalars) { return member.value }
        }
        return nil
    }

    static func string(_ value: MCPJSONValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    static func boolean(_ value: MCPJSONValue?) -> Bool? {
        guard case .boolean(let boolean) = value else { return nil }
        return boolean
    }

    static func pointer(_ path: String, in root: MCPJSONValue,
                        checkpoint: @Sendable () throws -> Void) throws -> MCPResultPointerMatch? {
        if path.isEmpty { return MCPResultPointerMatch(value: root, order: []) }
        guard path.first == "/" else { return nil }
        var value = root
        var order: [MCPResultPointerOrder] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
            try checkpoint()
            guard let token = try unescape(String(part), checkpoint: checkpoint) else { return nil }
            switch value {
            case .object:
                guard let next = try member(token, in: value, checkpoint: checkpoint) else { return nil }
                value = next
                order.append(.member(Array(token.utf8)))
            case .array(let values):
                guard validIndex(token), let index = Int(token), values.indices.contains(index) else { return nil }
                value = values[index]
                order.append(.element(index))
            default: return nil
            }
        }
        return MCPResultPointerMatch(value: value, order: order)
    }

    private static func validIndex(_ token: String) -> Bool {
        !token.isEmpty && (token == "0" || token.first != "0") && token.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func unescape(_ token: String, checkpoint: @Sendable () throws -> Void) throws -> String? {
        let scalars = Array(token.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if index.isMultiple(of: 64) { try checkpoint() }
            let scalar = scalars[index]
            index += 1
            if scalar.value != 0x7E { output.append(scalar); continue }
            guard index < scalars.count else { return nil }
            switch scalars[index].value {
            case 0x30: output.append("~")
            case 0x31: output.append("/")
            default: return nil
            }
            index += 1
        }
        return String(output)
    }
}

nonisolated struct MCPResultPointerMatch {
    let value: MCPJSONValue
    let order: [MCPResultPointerOrder]
}

nonisolated enum MCPResultPointerOrder: Equatable {
    case member([UInt8])
    case element(Int)
}
#endif
