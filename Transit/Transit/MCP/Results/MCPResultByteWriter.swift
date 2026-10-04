#if os(macOS)
import Foundation

/// Worker-local writer. Only validated document/fragment factories insert raw JSON.
/// The callback is discarded with this writer; returned bytes contain no closures.
nonisolated struct MCPResultByteWriter {
    private(set) var data = Data()
    private static let hex = Array("0123456789abcdef".utf8)
    private let checkpoint: @Sendable () throws -> Void

    init(checkpoint: @escaping @Sendable () throws -> Void) {
        self.checkpoint = checkpoint
    }

    mutating func literal(_ text: String) throws {
        try raw(Data(text.utf8))
    }

    mutating func raw(_ bytes: Data) throws {
        try checkpoint()
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let end = bytes.index(start, offsetBy: min(4_096, bytes.distance(from: start, to: bytes.endIndex)))
            data.append(contentsOf: bytes[start..<end])
            start = end
            try checkpoint()
        }
    }

    mutating func string(_ text: String) throws {
        try checkpoint()
        data.append(34)
        for (index, byte) in text.utf8.enumerated() {
            if index.isMultiple(of: 256) { try checkpoint() }
            switch byte {
            case 34: data.append(contentsOf: [92, 34])
            case 92: data.append(contentsOf: [92, 92])
            case 0...31:
                data.append(contentsOf: [92, 117, 48, 48, Self.hex[Int(byte >> 4)], Self.hex[Int(byte & 15)]])
            default: data.append(byte)
            }
        }
        data.append(34)
        try checkpoint()
    }

    mutating func field(_ name: String, _ value: String, first: Bool = false) throws {
        if !first { try literal(",") }
        try string(name)
        try literal(":")
        try string(value)
    }

}
#endif
