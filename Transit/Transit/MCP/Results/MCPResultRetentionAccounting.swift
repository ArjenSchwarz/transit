#if os(macOS)
import Foundation

/// Private-stage logical accounting. This temporary ledger never reaches a frozen
/// owner and never reserves store capacity. Checkpoints retain original failure types.
nonisolated struct MCPResultRetentionAccounting {
    private let checkpoint: @Sendable () throws -> Void
    private(set) var originalTextBytes = 0
    private(set) var sourceDocumentBytes = 0
    private(set) var sourceValueBytes = 0
    private(set) var presentationValueBytes = 0
    private(set) var fragmentBytes = 0
    private(set) var metadataDocumentBytes = 0
    private(set) var metadataValueBytes = 0
    private(set) var ownerReferenceBytes = 0

    init(checkpoint: @escaping @Sendable () throws -> Void) {
        self.checkpoint = checkpoint
    }

    mutating func measure(_ pages: [MCPResultPreparedPage]) throws {
        try checkpoint()
        ownerReferenceBytes = try Self.add(MemoryLayout<[MCPResultPreparedPage]>.stride,
                                           Self.slots(pages.count, stride: MemoryLayout<MCPResultPreparedPage>.stride))
        var seenPages: Set<ObjectIdentifier> = []
        var seenMetadata: Set<ObjectIdentifier> = []
        for page in pages {
            try checkpoint()
            guard seenPages.insert(ObjectIdentifier(page)).inserted else { continue }
            ownerReferenceBytes = try Self.add(ownerReferenceBytes, MemoryLayout<MCPResultPreparedMetadata?>.stride)
            originalTextBytes = try Self.add(originalTextBytes, utf8Bytes(page.source.originalText))
            var sourceDynamic = 0
            if let document = page.source.document {
                try checkpoint()
                sourceDocumentBytes = try Self.add(sourceDocumentBytes, document.originalUTF8.count)
                sourceDynamic = try treeDynamicBytes(document.value)
            }
            sourceValueBytes = try Self.add(sourceValueBytes,
                                            Self.add(MemoryLayout<MCPResultSource>.stride, sourceDynamic))
            presentationValueBytes = try Self.add(presentationValueBytes, presentationBytes(page.presentation))
            try checkpoint()
            fragmentBytes = try Self.add(fragmentBytes,
                Self.add(MemoryLayout<MCPResultToolFragment>.stride, page.fragment.encodedResult.count))
            if let owner = page.metadataOwner, seenMetadata.insert(ObjectIdentifier(owner)).inserted {
                try checkpoint()
                metadataDocumentBytes = try Self.add(metadataDocumentBytes, owner.value.document.originalUTF8.count)
                metadataValueBytes = try Self.add(metadataValueBytes,
                    Self.add(MemoryLayout<MCPResultMetadata>.stride, treeDynamicBytes(owner.value.document.value)))
            }
        }
        try checkpoint()
    }

    func total(originalCaptureIndexBytes: Int) throws -> Int {
        var bytes = originalCaptureIndexBytes
        for component in [originalTextBytes, sourceDocumentBytes, sourceValueBytes, presentationValueBytes,
                          fragmentBytes, metadataDocumentBytes, metadataValueBytes, ownerReferenceBytes] {
            try checkpoint()
            bytes = try Self.add(bytes, component)
        }
        return bytes
    }

    /// The enclosing source/metadata/member/array slot already contains this enum
    /// handle. Count only its indirect case payload and owned dynamic backing here.
    private func treeDynamicBytes(_ value: MCPJSONValue) throws -> Int {
        try checkpoint()
        switch value {
        case .object(let members):
            var bytes = try Self.add(MemoryLayout<[MCPJSONMember]>.stride,
                                    Self.slots(members.count, stride: MemoryLayout<MCPJSONMember>.stride))
            for member in members {
                try checkpoint()
                bytes = try Self.add(bytes, utf8Bytes(member.name))
                bytes = try Self.add(bytes, treeDynamicBytes(member.value))
            }
            return bytes
        case .array(let values):
            var bytes = try Self.add(MemoryLayout<[MCPJSONValue]>.stride,
                                    Self.slots(values.count, stride: MemoryLayout<MCPJSONValue>.stride))
            for value in values {
                try checkpoint()
                bytes = try Self.add(bytes, treeDynamicBytes(value))
            }
            return bytes
        case .string(let text): return try Self.add(MemoryLayout<String>.stride, utf8Bytes(text))
        case .number(let number): return try Self.add(MemoryLayout<MCPJSONNumber>.stride, utf8Bytes(number.lexeme))
        case .boolean: return MemoryLayout<Bool>.stride
        case .null: return 0
        }
    }

    private func presentationBytes(_ value: MCPResultPresentation) throws -> Int {
        try checkpoint()
        var bytes = try Self.add(MemoryLayout<MCPResultPresentation>.stride,
                                Self.slots(value.links.count, stride: MemoryLayout<MCPUnavailableLink>.stride))
        for link in value.links {
            try checkpoint()
            for text in [link.sourcePath, link.availability, link.reason] {
                bytes = try Self.add(bytes, utf8Bytes(text))
            }
        }
        // Recovery's enum/optional/array handles are embedded in presentation.
        if let mutation = value.recovery?.mutation {
            switch mutation {
            case .protectedWrite(let key):
                bytes = try Self.add(bytes, utf8Bytes(key.tool))
                bytes = try Self.add(bytes, utf8Bytes(key.idempotencyKey))
            case .unprotectedMaintenance(let tool):
                bytes = try Self.add(bytes, utf8Bytes(tool))
            case .applicationBatch(let items):
                bytes = try Self.add(bytes, Self.slots(items.count, stride: MemoryLayout<MCPBatchRecoveryItem>.stride))
                for item in items {
                    try checkpoint()
                    for text in [item.operation, item.originalKey.tool, item.originalKey.idempotencyKey] {
                        bytes = try Self.add(bytes, utf8Bytes(text))
                    }
                    if let itemId = item.itemId { bytes = try Self.add(bytes, utf8Bytes(itemId)) }
                }
            }
        }
        return bytes
    }

    /// Traverse instead of an unbounded String.UTF8View.count scan. Callers supply
    /// their original worker budget; this ledger creates no clock or new deadline.
    private func utf8Bytes(_ text: String) throws -> Int {
        var bytes = 0
        for _ in text.utf8 {
            if bytes.isMultiple(of: 256) { try checkpoint() }
            bytes = try Self.add(bytes, 1)
        }
        try checkpoint()
        return bytes
    }

    static func add(_ left: Int, _ right: Int) throws -> Int {
        guard left >= 0, right >= 0 else { throw MCPResultPreparationError.invalidAccounting }
        let (sum, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw MCPResultPreparationError.arithmeticOverflow }
        return sum
    }

    private static func slots(_ count: Int, stride: Int) throws -> Int {
        guard count >= 0, stride >= 0 else { throw MCPResultPreparationError.invalidAccounting }
        let (bytes, overflow) = count.multipliedReportingOverflow(by: stride)
        guard !overflow else { throw MCPResultPreparationError.arithmeticOverflow }
        return bytes
    }
}
#endif
