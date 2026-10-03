import Foundation
import CoreFoundation

/// Version 1 remains available for retained receipts across app upgrades.
enum MCPCanonicalJSON {
    enum Error: Swift.Error { case unsupportedVersion, invalidValue }

    static func request(_ arguments: [String: Any], version: Int = 1) throws -> String {
        var payload = arguments
        payload.removeValue(forKey: "idempotencyKey")
        return try encode(payload, version: version)
    }

    static func encode(_ value: Any, version: Int = 1) throws -> String {
        guard version == 1 else { throw Error.unsupportedVersion }
        if value is NSNull { return "null" }
        if let string = value as? String {
            let data = try JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
            guard let encoded = String(data: data, encoding: .utf8) else { throw Error.invalidValue }
            return encoded
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            guard number.doubleValue.isFinite else { throw Error.invalidValue }
            return try encodeNumber(number)
        }
        if let object = value as? [String: Any] {
            let fields = try object.keys.sorted().map { key in
                try encode(key) + ":" + encode(object[key]!)
            }
            return "{" + fields.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            return "[" + (try array.map { try encode($0) }).joined(separator: ",") + "]"
        }
        throw Error.invalidValue
    }

    /// Foundation emits a round-trippable JSON number. Normalize its decimal
    /// spelling without Decimal conversion, which rounds adjacent Doubles and
    /// cannot represent the full finite Double exponent range.
    private static func encodeNumber(_ number: NSNumber) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: number, options: [.fragmentsAllowed])
        guard var spelling = String(data: data, encoding: .utf8) else { throw Error.invalidValue }
        let negative = spelling.hasPrefix("-")
        if negative { spelling.removeFirst() }
        let parts = spelling.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        var exponent = 0
        if parts.count == 2 {
            guard let parsed = Int(parts[1]) else { throw Error.invalidValue }
            exponent = parsed
        }
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard mantissa.count <= 2 else { throw Error.invalidValue }
        var digits = mantissa.joined()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw Error.invalidValue }
        if mantissa.count == 2 { exponent -= mantissa[1].count }
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return "0" } // Positive and negative zero compare equally.
        while digits.last == "0" { digits.removeLast(); exponent += 1 }
        return (negative ? "-" : "") + digits + (exponent == 0 ? "" : "e" + String(exponent))
    }

}
