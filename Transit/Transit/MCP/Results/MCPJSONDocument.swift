#if os(macOS)
import Foundation

/// Immutable JSON values retain member order and validated numeric lexemes.
nonisolated indirect enum MCPJSONValue: Sendable, Equatable {
    case object([MCPJSONMember])
    case array([MCPJSONValue])
    case string(String)
    case number(MCPJSONNumber)
    case boolean(Bool)
    case null
}

nonisolated struct MCPJSONMember: Sendable, Equatable {
    let name: String
    let value: MCPJSONValue
}

nonisolated struct MCPJSONNumber: Sendable, Equatable {
    let lexeme: String

    fileprivate init(validatedLexeme: String) {
        lexeme = validatedLexeme
    }
}

/// Only the complete-value parser may construct an insertable raw fragment.
nonisolated struct MCPJSONDocument: Sendable, Equatable {
    let originalUTF8: Data
    let value: MCPJSONValue

    private init(originalUTF8: Data, value: MCPJSONValue) {
        self.originalUTF8 = originalUTF8
        self.value = value
    }

    /// The worker supplies its original deadline/cancellation check.
    static func parse(
        _ utf8: Data,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPJSONDocument {
        try checkpoint()
        guard String(data: utf8, encoding: .utf8) != nil else { throw MCPResultBoundaryError.invalidJSON }
        var scanner = MCPJSONScanner(bytes: Array(utf8), checkpoint: checkpoint)
        let value = try scanner.parse()
        try checkpoint()
        return MCPJSONDocument(originalUTF8: utf8, value: value)
    }

    static func parse(
        _ text: String,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPJSONDocument {
        return try parse(Data(text.utf8), checkpoint: checkpoint)
    }
}

/// Declaration-stage failures are explicit; no source or effect is fabricated.
nonisolated enum MCPResultBoundaryError: Error, Sendable, Equatable {
    case notImplemented
    case invalidJSON
    case resourceLimit
    case unsupportedEvidence
}

/// Iterative assembly bounds both parser stack and the resulting value tree.
nonisolated private struct MCPJSONScanner {
    let bytes: [UInt8]
    let checkpoint: @Sendable () throws -> Void
    private var offset = 0
    private var nextCheckpoint = 256
    private var frames: [MCPJSONFrame] = []
    private var root: MCPJSONValue?

    init(bytes: [UInt8], checkpoint: @escaping @Sendable () throws -> Void) {
        self.bytes = bytes
        self.checkpoint = checkpoint
    }

    mutating func parse() throws -> MCPJSONValue {
        try skipWhitespace()
        try readValue()
        while !frames.isEmpty {
            try skipWhitespace()
            try processTopFrame()
        }
        try skipWhitespace()
        guard offset == bytes.count, let root else { throw MCPResultBoundaryError.invalidJSON }
        return root
    }

    private mutating func processTopFrame() throws {
        let index = frames.count - 1
        switch frames[index].state {
        case .valueOrEnd:
            if peek == 0x5D { try closeContainer() } else { try readValue() }
        case .valueRequired: try readValue()
        case .keyOrEnd:
            if peek == 0x7D { try closeContainer() } else { try readKey() }
        case .keyRequired: try readKey()
        case .colon:
            guard try take() == 0x3A else { throw MCPResultBoundaryError.invalidJSON }
            frames[index].state = .valueRequired
        case .commaOrEnd: try readSeparator()
        }
    }

    private mutating func readSeparator() throws {
        let index = frames.count - 1
        let closing: UInt8 = frames[index].isObject ? 0x7D : 0x5D
        if peek == closing {
            try closeContainer()
        } else {
            guard try take() == 0x2C else { throw MCPResultBoundaryError.invalidJSON }
            frames[index].state = frames[index].isObject ? .keyRequired : .valueRequired
        }
    }

    private mutating func readValue() throws {
        guard let byte = peek else { throw MCPResultBoundaryError.invalidJSON }
        switch byte {
        case 0x7B, 0x5B:
            guard frames.count < 32 else { throw MCPResultBoundaryError.resourceLimit }
            let isObject = try take() == 0x7B
            frames.append(MCPJSONFrame(isObject: isObject, state: isObject ? .keyOrEnd : .valueOrEnd))
        case 0x22: try attach(.string(readString()))
        case 0x74: try readLiteral("true"); attach(.boolean(true))
        case 0x66: try readLiteral("false"); attach(.boolean(false))
        case 0x6E: try readLiteral("null"); attach(.null)
        case 0x2D, 0x30...0x39: try attach(.number(MCPJSONNumber(validatedLexeme: readNumber())))
        default: throw MCPResultBoundaryError.invalidJSON
        }
    }

    private mutating func readKey() throws {
        let key = try readString()
        let index = frames.count - 1
        // Swift String hashing uses canonical equivalence; JSON names do not.
        guard frames[index].keys.insert(key.unicodeScalars.map(\.value)).inserted else {
            throw MCPResultBoundaryError.invalidJSON
        }
        frames[index].pendingKey = key
        frames[index].state = .colon
    }

    private mutating func closeContainer() throws {
        _ = try take()
        let frame = frames.removeLast()
        attach(frame.isObject ? .object(frame.members) : .array(frame.values))
    }

    private mutating func attach(_ value: MCPJSONValue) {
        guard !frames.isEmpty else { root = value; return }
        let index = frames.count - 1
        if frames[index].isObject {
            // Only the colon/value state can reach this path with an object.
            if let key = frames[index].pendingKey {
                frames[index].members.append(MCPJSONMember(name: key, value: value))
                frames[index].pendingKey = nil
            }
        } else {
            frames[index].values.append(value)
        }
        frames[index].state = .commaOrEnd
    }

    private var peek: UInt8? { offset < bytes.count ? bytes[offset] : nil }

    private mutating func take() throws -> UInt8 {
        guard let byte = peek else { throw MCPResultBoundaryError.invalidJSON }
        offset += 1
        if offset >= nextCheckpoint {
            try checkpoint()
            nextCheckpoint = offset + 256
        }
        return byte
    }

    private mutating func skipWhitespace() throws {
        while let byte = peek, [0x20, 0x09, 0x0A, 0x0D].contains(byte) { _ = try take() }
    }
}

nonisolated private extension MCPJSONScanner {
    mutating func readLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            guard try take() == byte else { throw MCPResultBoundaryError.invalidJSON }
        }
    }

    mutating func readNumber() throws -> String {
        let start = offset
        if peek == 0x2D { _ = try take() }
        if peek == 0x30 {
            _ = try take()
        } else {
            guard let byte = peek, (0x31...0x39).contains(byte) else { throw MCPResultBoundaryError.invalidJSON }
            try digits()
        }
        if peek == 0x2E { _ = try take(); try requiredDigits() }
        if peek == 0x65 || peek == 0x45 {
            _ = try take()
            if peek == 0x2B || peek == 0x2D { _ = try take() }
            try requiredDigits()
        }
        guard let token = String(bytes: bytes[start..<offset], encoding: .utf8) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        return token
    }

    mutating func requiredDigits() throws {
        guard let byte = peek, (0x30...0x39).contains(byte) else { throw MCPResultBoundaryError.invalidJSON }
        try digits()
    }

    mutating func digits() throws {
        while let byte = peek, (0x30...0x39).contains(byte) { _ = try take() }
    }

    mutating func readString() throws -> String {
        guard try take() == 0x22 else { throw MCPResultBoundaryError.invalidJSON }
        var decoded: [UInt8] = []
        while true {
            let byte = try take()
            if byte == 0x22 { break }
            guard byte >= 0x20 else { throw MCPResultBoundaryError.invalidJSON }
            if byte != 0x5C { decoded.append(byte); continue }
            try decoded.append(contentsOf: readEscape())
        }
        guard let text = String(bytes: decoded, encoding: .utf8) else { throw MCPResultBoundaryError.invalidJSON }
        return text
    }

    mutating func readEscape() throws -> [UInt8] {
        switch try take() {
        case 0x22: return [0x22]
        case 0x5C: return [0x5C]
        case 0x2F: return [0x2F]
        case 0x62: return [0x08]
        case 0x66: return [0x0C]
        case 0x6E: return [0x0A]
        case 0x72: return [0x0D]
        case 0x74: return [0x09]
        case 0x75: return try Array(readUnicodeEscape().utf8)
        default: throw MCPResultBoundaryError.invalidJSON
        }
    }

    mutating func readUnicodeEscape() throws -> String {
        var code = try hexQuad()
        if (0xD800...0xDBFF).contains(code) {
            guard try take() == 0x5C, try take() == 0x75 else { throw MCPResultBoundaryError.invalidJSON }
            let low = try hexQuad()
            guard (0xDC00...0xDFFF).contains(low) else { throw MCPResultBoundaryError.invalidJSON }
            code = 0x10000 + (code - 0xD800) * 0x400 + low - 0xDC00
        } else if (0xDC00...0xDFFF).contains(code) {
            throw MCPResultBoundaryError.invalidJSON
        }
        guard let scalar = UnicodeScalar(code) else { throw MCPResultBoundaryError.invalidJSON }
        return String(scalar)
    }

    mutating func hexQuad() throws -> UInt32 {
        var code: UInt32 = 0
        for _ in 0..<4 {
            let byte = try take()
            let digit: UInt8
            switch byte {
            case 0x30...0x39: digit = byte - 0x30
            case 0x41...0x46: digit = byte - 0x41 + 10
            case 0x61...0x66: digit = byte - 0x61 + 10
            default: throw MCPResultBoundaryError.invalidJSON
            }
            code = code * 16 + UInt32(digit)
        }
        return code
    }
}

nonisolated private struct MCPJSONFrame {
    let isObject: Bool
    var state: MCPJSONFrameState
    var values: [MCPJSONValue] = []
    var members: [MCPJSONMember] = []
    var keys: Set<[UInt32]> = []
    var pendingKey: String?
}

nonisolated private enum MCPJSONFrameState {
    case valueOrEnd, valueRequired, keyOrEnd, keyRequired, colon, commaOrEnd
}
#endif
