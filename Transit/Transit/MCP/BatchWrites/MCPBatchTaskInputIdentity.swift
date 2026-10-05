#if os(macOS)
import Foundation

/// Opaque JSON identities use decoded scalar spelling, never Swift's canonical
/// String equivalence. Valid UTF-8 is a unique encoding of those scalars.
nonisolated struct MCPBatchTaskInputIdentity: Hashable {
    let value: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }

    func hash(into hasher: inout Hasher) {
        for byte in value.utf8 { hasher.combine(byte) }
    }
}

nonisolated enum MCPBatchTaskInputValue {
    static func closedField(_ members: [MCPJSONMember], allowed: [String]) -> String? {
        var seen: Set<MCPBatchTaskInputIdentity> = []
        for member in members {
            guard allowed.contains(where: { $0.utf8.elementsEqual(member.name.utf8) }),
                  seen.insert(MCPBatchTaskInputIdentity(value: member.name)).inserted else { return member.name }
        }
        return nil
    }

    static func member(_ name: String, in members: [MCPJSONMember]) -> MCPJSONValue? {
        members.first { $0.name.utf8.elementsEqual(name.utf8) }?.value
    }

    static func string(_ value: MCPJSONValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }

    static func key(_ text: String) -> Bool {
        guard (1...128).contains(text.utf8.count) else { return false }
        return text.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
                [46, 95, 58, 45].contains($0)
        }
    }

    /// Mathematical integral JSON numbers must fit Int exactly. A Double bridge
    /// could round a fraction to one or underflow it to zero before validation.
    static func integer(_ value: MCPJSONValue) -> Int? {
        guard case .number(let number) = value else { return nil }
        var spelling = number.lexeme[...]
        let negative = spelling.first == "-"
        if negative { spelling.removeFirst() }
        let pieces = spelling.split { $0 == "e" || $0 == "E" }
        let mantissa = pieces[0].split(separator: ".")
        let fractionCount = mantissa.count == 2 ? mantissa[1].utf8.count : 0
        let digits = mantissa.joined()
        var first = digits.startIndex
        var end = digits.endIndex
        while first < end && digits[first] == "0" { first = digits.index(after: first) }
        if first == end { return 0 }
        while end > first && digits[digits.index(before: end)] == "0" { end = digits.index(before: end) }
        let exponent: Int
        if pieces.count == 2 {
            guard let parsed = Int(pieces[1]) else { return nil }
            exponent = parsed
        } else { exponent = 0 }
        let (scale, scaleOverflow) = exponent.subtractingReportingOverflow(fractionCount)
        let trailingZeros = digits.distance(from: end, to: digits.endIndex)
        let (shift, shiftOverflow) = scale.addingReportingOverflow(trailingZeros)
        let significantCount = digits.distance(from: first, to: end)
        guard !scaleOverflow, !shiftOverflow, shift >= 0, significantCount <= 19,
              shift <= 19 - significantCount else { return nil }
        let integer = (negative ? "-" : "") + String(digits[first..<end]) + String(repeating: "0", count: shift)
        return Int(integer)
    }
}
#endif
