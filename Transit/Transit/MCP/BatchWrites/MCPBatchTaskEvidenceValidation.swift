#if os(macOS)
import Foundation

nonisolated enum MCPBatchTaskEvidenceValidation {
    /// Equality to one uses decimal digits/exponent, never Double/Decimal.
    /// The common parser already validated the complete numeric lexeme.
    static func numberIsOne(_ value: MCPJSONValue?) -> Bool {
        guard case .number(let number) = value, !number.lexeme.hasPrefix("-") else { return false }
        let pieces = number.lexeme.split { $0 == "e" || $0 == "E" }
        let exponent: Int
        if pieces.count == 2 {
            guard let parsed = Int(pieces[1]) else { return false }
            exponent = parsed
        } else { exponent = 0 }
        let mantissa = pieces[0].split(separator: ".")
        let fractionCount = mantissa.count == 2 ? mantissa[1].utf8.count : 0
        let digits = Array(mantissa.joined().utf8)
        var first = 0
        var end = digits.count
        while first < end && digits[first] == 48 { first += 1 }
        while end > first && digits[end - 1] == 48 { end -= 1 }
        guard end - first == 1, digits[first] == 49 else { return false }
        return exponent == fractionCount - (digits.count - end)
    }

    static func revision(_ value: MCPJSONValue?) -> Bool {
        guard case .string(let text) = value, text.utf8.count == 67 else { return false }
        let bytes = Array(text.utf8)
        return bytes.prefix(3).elementsEqual([114, 49, 58]) &&
            bytes.dropFirst(3).allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Parsing alone can normalize invalid dates. Require canonical UTC
    /// millisecond spelling and formatter roundtrip before comparing instants.
    static func timestamp(_ value: MCPJSONValue?) -> Date? {
        guard case .string(let text) = value, text.utf8.count == 24 else { return nil }
        let bytes = Array(text.utf8)
        let separators: [Int: UInt8] = [4: 45, 7: 45, 10: 84, 13: 58, 16: 58, 19: 46, 23: 90]
        for (index, byte) in bytes.enumerated() {
            if let separator = separators[index] {
                guard byte == separator else { return nil }
            } else if !(48...57).contains(byte) { return nil }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
}
#endif
