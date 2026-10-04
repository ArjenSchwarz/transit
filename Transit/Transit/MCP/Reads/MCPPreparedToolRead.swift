#if os(macOS)
import Foundation

/// Tool-level fragments have no RPC identifier. The transport selects final encoded RPC bytes.
nonisolated struct MCPPreparedToolRead: Sendable {
    let result: MCPToolResult
    let encodedToolResult: Data
    let frozenMetadataBytes: Data?
    let publications: [any MCPPreparedPublication]
    let preparedResultPage: MCPResultPreparedPage?

    private init(result: MCPToolResult, encodedToolResult: Data, frozenMetadataBytes: Data?,
                 publications: [any MCPPreparedPublication], preparedResultPage: MCPResultPreparedPage?) {
        self.result = result
        self.encodedToolResult = encodedToolResult
        self.frozenMetadataBytes = frozenMetadataBytes
        self.publications = publications
        self.preparedResultPage = preparedResultPage
    }

    /// Attaching a reservation cannot fail after its ownership has been allocated.
    func attaching(_ publications: [any MCPPreparedPublication]) -> Self {
        Self(result: result, encodedToolResult: encodedToolResult, frozenMetadataBytes: frozenMetadataBytes,
             publications: publications, preparedResultPage: preparedResultPage)
    }

    /// Carries the sealed immutable owner without rebuilding existing tool bytes or metadata.
    func attachingPreparedResultPage(_ page: MCPResultPreparedPage) -> Self {
        Self(result: result, encodedToolResult: encodedToolResult, frozenMetadataBytes: frozenMetadataBytes,
             publications: publications, preparedResultPage: page)
    }

    /// Replays a sealed page without decoding frozen metadata or reparsing/reclassifying its source.
    init(preparedResultPage page: MCPResultPreparedPage, frozenMetadataBytes: Data?,
         publications: [any MCPPreparedPublication] = []) {
        result = MCPToolResult(content: [.text(page.source.originalText)], isError: page.source.originalIsError)
        encodedToolResult = page.fragment.encodedResult
        self.frozenMetadataBytes = frozenMetadataBytes
        self.publications = publications
        preparedResultPage = page
    }

    init(text: String, isError: Bool? = nil, metadata: MCPReadResultMetadata? = nil,
         frozenMetadataBytes: Data? = nil, publications: [any MCPPreparedPublication] = [],
         preparedResultPage: MCPResultPreparedPage? = nil,
         providerEvidence: MCPResultProviderEvidence? = nil) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try frozenMetadataBytes ?? metadata.map { try encoder.encode($0) }
        let resultMetadata: MCPToolResultMetadata?
        if let metadata { resultMetadata = MCPToolResultMetadata(read: metadata) } else if let bytes {
            let original = try JSONDecoder().decode(ReadCaptureMetadata.self, from: bytes)
            resultMetadata = MCPToolResultMetadata(read: .capture(original))
        } else { resultMetadata = nil }
        result = MCPToolResult(content: [.text(text)], isError: isError, metadata: resultMetadata,
                               providerEvidence: providerEvidence)
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
        self.preparedResultPage = preparedResultPage
    }
}
#endif
