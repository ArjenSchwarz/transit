#if os(macOS)
import Foundation

/// Tool-level fragments have no RPC identifier. The transport selects final encoded RPC bytes.
nonisolated struct MCPPreparedToolRead: Sendable {
    let result: MCPToolResult
    let encodedToolResult: Data
    let frozenMetadataBytes: Data?
    let publications: [any MCPPreparedPublication]

    private init(result: MCPToolResult, encodedToolResult: Data, frozenMetadataBytes: Data?,
                 publications: [any MCPPreparedPublication]) {
        self.result = result
        self.encodedToolResult = encodedToolResult
        self.frozenMetadataBytes = frozenMetadataBytes
        self.publications = publications
    }

    /// Attaching a reservation cannot fail after its ownership has been allocated.
    func attaching(_ publications: [any MCPPreparedPublication]) -> Self {
        Self(result: result, encodedToolResult: encodedToolResult, frozenMetadataBytes: frozenMetadataBytes,
             publications: publications)
    }

    init(text: String, isError: Bool? = nil, metadata: MCPReadResultMetadata? = nil,
         frozenMetadataBytes: Data? = nil, publications: [any MCPPreparedPublication] = []) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try frozenMetadataBytes ?? metadata.map { try encoder.encode($0) }
        let resultMetadata: MCPToolResultMetadata?
        if let metadata { resultMetadata = MCPToolResultMetadata(read: metadata) } else if let bytes {
            let original = try JSONDecoder().decode(ReadCaptureMetadata.self, from: bytes)
            resultMetadata = MCPToolResultMetadata(read: .capture(original))
        } else { resultMetadata = nil }
        result = MCPToolResult(content: [.text(text)], isError: isError, metadata: resultMetadata)
        var encoded = try encoder.encode(MCPToolResult(content: [.text(text)], isError: isError))
        if let bytes {
            // Insert the frozen metadata JSON verbatim; cursor replay does not assess or relabel it.
            encoded.removeLast()
            encoded.append(Data(",\"_meta\":{\"me.nore.ig.transit/read\":".utf8))
            encoded.append(bytes)
            encoded.append(Data("}}".utf8))
        }
        encodedToolResult = encoded
        self.frozenMetadataBytes = bytes
        self.publications = publications
    }
}
#endif
