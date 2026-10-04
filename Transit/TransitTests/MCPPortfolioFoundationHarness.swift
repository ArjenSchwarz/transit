#if os(macOS)
import Foundation
import Hummingbird
import HTTPTypes
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
import Testing
@testable import Transit

/// Minimal synthetic read adapter, not final MCP dispatch or summary aggregation.
nonisolated enum MCPPortfolioFoundationHarness {
    static let timeout = Data("{\"error\":\"READ_TIMEOUT\"}".utf8)
    static let busy = Data("{\"error\":\"READ_BUSY\"}".utf8)
    static let capacity = Data("{\"error\":\"QUERY_CAPACITY_EXCEEDED\"}".utf8)

    static func prepareCapture(_ view: CapturedReadView) throws -> PreparedReadResult {
        guard case .completePortfolio = view.completeness else { throw MCPReadCaptureError.incoherentCapture }
        guard view.captureScope != .selectedQuery else { throw MCPReadCaptureError.incoherentCapture }
        let selectedProjects: Set<LocalRecordKey>?
        switch view.captureScope {
        case .wholePortfolio: selectedProjects = nil
        case .projects(let keys): selectedProjects = Set(keys)
        case .selectedQuery: throw MCPReadCaptureError.incoherentCapture
        }
        let commentKeys = Set(view.comments.map(\.physicalKey))
        var records: [Data] = []
        var evidence: [PortfolioFoundationTaskEvidence] = []
        for task in view.tasks {
            let selected = selectedProjects.map { projects in
                task.projectKey.map { projects.contains($0) } ?? false
            } ?? true
            if selected {
                guard let record = task.fullRecordWithoutCommentsJSON, let revision = task.revision,
                      revision.hasPrefix("r1:"), Set(task.commentKeys).isSubset(of: commentKeys) else {
                    throw MCPReadCaptureError.incoherentCapture
                }
                records.append(record)
            }
            // Preserve the original identity closure; full records/counts use only
            // declared physical scope. This is fixture encoding, not production validation.
            evidence.append(PortfolioFoundationTaskEvidence(
                id: task.id, physicalKey: task.physicalKey.encodedIdentifier,
                projectKey: task.projectKey?.encodedIdentifier, milestoneKey: task.milestoneKey?.encodedIdentifier,
                commentKeys: task.commentKeys.map(\.encodedIdentifier), rawStatus: task.rawStatus,
                effectiveStatus: task.effectiveStatus, revision: task.revision))
        }
        let envelope = PortfolioFoundationCaptureEnvelope(
            asOf: view.metadata.asOf, snapshotId: view.metadata.snapshotId, metadata: view.metadata,
            taskCount: records.count, records: records, taskEvidence: evidence,
            projects: view.projects.map(\.selectedRecordJSON), milestones: view.milestones.map(\.selectedRecordJSON),
            comments: view.comments.map {
                PortfolioFoundationCommentEvidence(id: $0.id, physicalKey: $0.physicalKey.encodedIdentifier,
                    taskKey: $0.taskKey?.encodedIdentifier, storedTaskID: $0.storedTaskID,
                    creationDate: $0.creationDate)
            })
        let encoded = try JSONEncoder().encode(envelope)
        return result(encoded.count <= 16 * 1_024 * 1_024 ? encoded : capacity)
    }

    static func result(_ bytes: Data, publications: [any MCPPreparedPublication] = []) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: publications,
            publicationErrors: PreencodedPublicationErrors(busy: busy, expired: timeout, capacity: busy))
    }

    @concurrent static func route(
        _ response: @escaping @Sendable () async -> Response
    ) async throws -> Data {
        let router = Router(context: MCPRequestContext.self)
        router.post("/portfolio-fixture") { _, _ in await response() }
        let loop = NIOAsyncTestingEventLoop()
        var ownedChannel: NIOAsyncTestingChannel?
        do {
            let channel = try await NIOAsyncTestingChannel(loop: loop) { _ in }
            ownedChannel = channel
            let context = MCPRequestContext(source: ApplicationRequestContextSource(
                channel: channel, logger: Logger(label: "portfolio-foundation")))
            let request = Request(head: HTTPRequest(method: .post, scheme: "http", authority: "localhost",
                                                   path: "/portfolio-fixture"),
                                  body: RequestBody(buffer: ByteBuffer()))
            let output = try await router.buildResponder().respond(to: request, context: context)
            let writer = PortfolioFoundationResponseWriter()
            try await output.body.write(writer)
            let bytes = Data(buffer: writer.bytes.withLockedValue { $0 })
            let leftovers = try await channel.finish(acceptAlreadyClosed: true)
            #expect(leftovers.isClean)
            await loop.shutdownGracefully()
            return bytes
        } catch {
            if let channel = ownedChannel {
                do {
                    let leftovers = try await channel.finish(acceptAlreadyClosed: true)
                    #expect(leftovers.isClean)
                } catch { Issue.record("Foundation test channel cleanup failed: \(error)") }
            }
            await loop.shutdownGracefully()
            throw error
        }
    }
}

private nonisolated struct PortfolioFoundationCaptureEnvelope: Encodable {
    let asOf: String
    let snapshotId: String
    let metadata: ReadCaptureMetadata
    let taskCount: Int
    let records: [Data]
    let taskEvidence: [PortfolioFoundationTaskEvidence]
    let projects: [Data]
    let milestones: [Data]
    let comments: [PortfolioFoundationCommentEvidence]
}

private nonisolated struct PortfolioFoundationTaskEvidence: Encodable {
    let id: UUID
    let physicalKey: Data
    let projectKey: Data?
    let milestoneKey: Data?
    let commentKeys: [Data]
    let rawStatus: String
    let effectiveStatus: String
    let revision: String?
}

private nonisolated struct PortfolioFoundationCommentEvidence: Encodable {
    let id: UUID
    let physicalKey: Data
    let taskKey: Data?
    let storedTaskID: UUID?
    let creationDate: Date
}

actor PortfolioFoundationCompletion {
    private var completed = false
    func finish() { completed = true }
    var isFinished: Bool { completed }
}

private nonisolated final class PortfolioFoundationResponseWriter: ResponseBodyWriter {
    let bytes = NIOLockedValueBox(ByteBuffer())
    func write(_ buffer: ByteBuffer) async throws { _ = bytes.withLockedValue { $0.writeImmutableBuffer(buffer) } }
    func finish(_: HTTPFields?) async throws {}
}

nonisolated final class PortfolioFoundationPublication: MCPPreparedPublication, @unchecked Sendable {
    let publicationStoreID = MCPPublicationStoreID(rawValue: UUID())
    let domain: MCPReadPublicationDomain
    private var committed = false
    private var discarded = false
    init(domain: MCPReadPublicationDomain) { self.domain = domain }
    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection? { nil }
    func commitLocked(in domain: MCPReadPublicationDomain) { if !discarded { committed = true } }
    func discardLocked(in domain: MCPReadPublicationDomain) { if !committed { discarded = true } }
    var counts: [Bool] { domain.withLock { [committed, discarded] } }
}
#endif
