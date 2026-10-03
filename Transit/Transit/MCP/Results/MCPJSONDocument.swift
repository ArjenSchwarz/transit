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
        checkpoint: @Sendable () throws -> Void = {}
    ) throws -> MCPJSONDocument {
        throw MCPResultBoundaryError.notImplemented
    }

    static func parse(
        _ text: String,
        checkpoint: @Sendable () throws -> Void = {}
    ) throws -> MCPJSONDocument {
        throw MCPResultBoundaryError.notImplemented
    }
}

/// Declaration-stage failures are explicit; no source or effect is fabricated.
nonisolated enum MCPResultBoundaryError: Error, Sendable, Equatable {
    case notImplemented
    case invalidJSON
    case resourceLimit
    case unsupportedEvidence
}
#endif
