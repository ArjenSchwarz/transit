#if os(macOS)
import Foundation

/// Test-only complete-envelope structure oracle, independent of Transit parsing.
/// Foundation's numeric range cannot validate lossless JSON number tokens. Strictly
/// validate those tokens first, then replace them only in a disposable copy. The
/// decoded tree is discarded; raw-fragment assertions always use original bytes.
nonisolated enum MCPJSONEnvelopeFixtureValidation {
    static func validate(_ data: Data) throws {
        let bytes = Array(data)
        var disposable = Data()
        var offset = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            if byte == 34 {
                let end = try stringEnd(bytes, offset)
                disposable.append(contentsOf: bytes[offset..<end])
                offset = end
            } else if byte == 45 || (48...57).contains(byte) {
                offset = try numberEnd(bytes, offset)
                disposable.append(48)
            } else {
                guard byte != 43, byte != 46 else { throw ValidationError.invalidNumber }
                disposable.append(byte)
                offset += 1
            }
        }
        _ = try JSONSerialization.jsonObject(with: disposable, options: [.fragmentsAllowed])
    }

    private static func stringEnd(_ bytes: [UInt8], _ start: Int) throws -> Int {
        var offset = start + 1
        while offset < bytes.count {
            if bytes[offset] == 92 { offset += 2; continue }
            if bytes[offset] == 34 { return offset + 1 }
            offset += 1
        }
        throw ValidationError.unterminatedString
    }

    private static func numberEnd(_ bytes: [UInt8], _ start: Int) throws -> Int {
        var offset = start
        func peek() -> UInt8? { offset < bytes.count ? bytes[offset] : nil }
        func digits() {
            while let byte = peek(), (48...57).contains(byte) { offset += 1 }
        }
        func requiredDigits() throws {
            guard let byte = peek(), (48...57).contains(byte) else { throw ValidationError.invalidNumber }
            digits()
        }
        if peek() == 45 { offset += 1 }
        if peek() == 48 {
            offset += 1
        } else {
            guard let byte = peek(), (49...57).contains(byte) else { throw ValidationError.invalidNumber }
            digits()
        }
        if peek() == 46 { offset += 1; try requiredDigits() }
        if peek() == 69 || peek() == 101 {
            offset += 1
            if peek() == 43 || peek() == 45 { offset += 1 }
            try requiredDigits()
        }
        if let next = peek(), ![9, 10, 13, 32, 44, 93, 125].contains(next) {
            throw ValidationError.invalidNumber
        }
        return offset
    }

    private enum ValidationError: Error { case invalidNumber, unterminatedString }
}
#endif
