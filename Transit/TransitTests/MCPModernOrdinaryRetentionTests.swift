#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPModernOrdinaryRetentionTests {
    @Test func omittedCommentsKeepSavedCanonicalRevisionAfterLaterEditsAndNewIDs() throws {
        let models = try TestModelContainer()
        models.context.autosaveEnabled = false
        let project = Project(name: "Original parent", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Original task", type: .feature, project: project, displayID: .permanent(16))
        let comment = Comment(content: "Original comment", authorName: "Fixture", isAgent: true, task: task)
        models.context.insert(project)
        models.context.insert(task)
        models.context.insert(comment)
        try models.context.save()
        let savedRevision = try MCPRecordSnapshot.task(task, in: models.context).revision
        let capture = try MCPReadCaptureBuilder(container: models.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
                completeness: .selectedRead, includeComments: false))
        let capturedTask = try #require(capture.tasks.first)
        #expect(capturedTask.revision == savedRevision)
        #expect(capturedTask.requestedCommentRecordsJSON == nil)
        #expect(capture.comments.count == 1)
        let recordBytes = try #require(capturedTask.fullRecordWithoutCommentsJSON)
        let text = try #require(String(data: recordBytes, encoding: .utf8))
        let metadata = try JSONEncoder().encode(capture.metadata)
        let pages = try preparedPages([text, text], metadata: metadata)
        let bundle = try retainedBundle(pages)
        let clock = Clock()
        clock.instant = capture.createdAt
        let domain = MCPReadPublicationDomain(testingInstant: clock.instant)
        let store = MCPTaskQuerySnapshotStore(now: { clock.instant }, domain: domain)
        let cursor = UUID().uuidString
        let reservation = try #require(try store.prepare(preparedBundle: bundle, cursors: [cursor],
            deadline: capture.retentionDeadline, operationID: UUID(), metadataBytes: metadata, policy: .cached))
        try commit(reservation, domain: domain)
        try saveLaterEdits(comment: comment, task: task, project: project, context: models.context)
        #expect(try MCPRecordSnapshot.task(task, in: models.context).revision != savedRevision)
        let retained = try store.retainedPage(for: cursor)
        let owner = try #require(retained.preparedResultPage)
        #expect(owner === pages[1])
        #expect(retained.text.utf8.elementsEqual(text.utf8))
        #expect(retained.metadataBytes == metadata && retained.policy == .cached)
        let frozen = try #require(owner.source.document?.value)
        #expect(MCPResultEncoderFixtures.field("revision", in: frozen) == .string(savedRevision))
        #expect(MCPResultEncoderFixtures.field("comments", in: frozen) == nil)
        for id in [JSONRPCId.string("after-edit"), .integer(16)] {
            let prepared = try MCPPreparedToolRead(text: retained.text, frozenMetadataBytes: retained.metadataBytes,
                preparedResultPage: owner)
            let actual = try MCPModernProviderBinding.read(prepared, id: id, tool: "query_tasks")
            let expected = try MCPResultEncoder.encode(fragment: pages[1].fragment, id: id)
            #expect(actual == expected)
        }
        clock.instant += .seconds(300)
        domain.setTestingInstant(clock.instant)
        #expect(throws: (any Error).self) { try store.retainedPage(for: cursor) }
    }

    @Test func expandedOwnersStayPrivateAndDiscardClearsAllPendingBytes() throws {
        let clock = Clock()
        let domain = MCPReadPublicationDomain(testingInstant: clock.instant)
        let store = MCPTaskQuerySnapshotStore(now: { clock.instant }, domain: domain)
        let pages = try preparedPages(["[]", #"{"future":1E-9999}"#])
        let bundle = try retainedBundle(pages)
        let cursor = UUID().uuidString
        let reservation = try #require(try store.prepare(preparedBundle: bundle, cursors: [cursor],
            deadline: clock.instant + .seconds(300), operationID: UUID(), metadataBytes: nil, policy: .cached))
        defer { domain.withLock { reservation.discardLocked(in: domain) } }
        let pending = try domain.accounting(for: store.publicationStoreID)
        #expect(pending.visibleBytes == 0 && pending.pendingBytes == bundle.charge.totalBytes)
        #expect(throws: (any Error).self) { try store.retainedPage(for: cursor) }
        domain.withLock { reservation.discardLocked(in: domain); reservation.discardLocked(in: domain) }
        let empty = try domain.accounting(for: store.publicationStoreID)
        #expect(empty.pendingBytes == 0 && empty.visibleBytes == 0)
        #expect(throws: (any Error).self) { try store.retainedPage(for: cursor) }
    }

    @Test func expandedCapacityRejectsWholeWhileReusableBudgetIsIndependent() throws {
        let pages = try preparedPages(["[]", #"{"future":null}"#])
        let bundle = try retainedBundle(pages)
        let domain = MCPReadPublicationDomain()
        let store = MCPTaskQuerySnapshotStore(maxBytes: bundle.charge.totalBytes - 1, domain: domain)
        let reusable = try MCPReusableSnapshotStore(domain: domain)
        do {
            _ = try store.prepare(preparedBundle: bundle, cursors: [UUID().uuidString],
                deadline: .now + .seconds(300), operationID: UUID(), metadataBytes: nil, policy: .cached)
            Issue.record("Expanded ordinary capacity unexpectedly accepted")
        } catch let error as MCPTaskQueryError {
            #expect(error.code == "QUERY_CAPACITY_EXCEEDED")
        }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        #expect(try domain.accounting(for: reusable.publicationStoreID).visibleBytes == 0)
        #expect(try domain.accounting(for: reusable.publicationStoreID).pendingBytes == 0)
    }

    @Test func pagePreparerGetsAllPrivatePagesAndExactOriginalOperationBeforeFailure() async throws {
        let models = try TestModelContainer()
        let snapshots = MCPTaskQuerySnapshotStore()
        let service = MCPReadService(source: MCPReadCaptureBuilder(container: models.container,
            fence: .actorOnlyTestFixture), monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil),
            snapshots: snapshots, pagePreparer: { pages, tool, original in
                #expect(pages.map { $0.result.content.first?.text } == ["[]", "null", "false"])
                #expect(tool == "query_tasks" && original.shouldContinue())
                throw PreparationFault.blockedParser
            })
        let coordinator = MCPReadCoordinator(domain: snapshots.domain)
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            await MainActor.run {
                do {
                    let reads = try ["[]", "null", "false"].map { try MCPPreparedToolRead(text: $0) }
                    #expect(throws: PreparationFault.blockedParser) {
                        try service.preparePrivatePages(reads, tool: "query_tasks", operation: operation)
                    }
                    return Self.response(Data("observed".utf8))
                } catch {
                    Issue.record("Page-preparer control failed: \(error)")
                    return Self.response(Data("failed".utf8))
                }
            }
        }
        #expect(bytes == Data("observed".utf8))
        #expect(snapshots.retainedBytes == 0)
        for _ in 0..<100 where coordinator.unfinishedCount != 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test func laterParserFailureLeavesNoPreparedPublicationOrCursor() throws {
        let store = MCPTaskQuerySnapshotStore()
        #expect(throws: MCPResultBoundaryError.invalidJSON) { try preparedPages(["[]", "{broken"]) }
        #expect(store.retainedBytes == 0)
    }

    private func preparedPages(_ texts: [String], metadata: Data? = nil) throws -> [MCPResultPreparedPage] {
        let owner: MCPResultPreparedMetadata?
        if let metadata {
            let tool = try MCPPreparedToolRead(text: "null", frozenMetadataBytes: metadata)
            let value = try #require(try MCPResultProviderAdapters.metadata(
                result: tool.result, frozenReadBytes: metadata))
            owner = try MCPResultPreparation.metadata(value: value)
        } else { owner = nil }
        return try texts.map { text in
            try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: text, isError: nil,
                origin: .generatedJSON, evidence: .established,
                context: MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                    mutationRecovery: nil, entityPositions: []), metadataOwner: owner))
        }
    }

    private func saveLaterEdits(comment: Transit.Comment, task: TransitTask, project: Project,
                                context: ModelContext) throws {
        comment.content = "Later saved comment"
        task.name = "Later saved task"
        project.name = "Later parent"
        try context.save()
    }

    private func retainedBundle(_ pages: [MCPResultPreparedPage]) throws -> MCPResultRetainedBundle {
        try MCPResultPreparation.prepare(pages: pages, budget: MCPResultRetentionBudget(store: .ordinary,
            originalCaptureIndexBytes: 0, visibleBytes: 0, pendingBytes: 0))
    }

    private func commit(_ publication: MCPPublicationReservation, domain: MCPReadPublicationDomain) throws {
        try domain.withLock {
            if let rejection = publication.validateLocked(in: domain) { throw rejection }
            publication.commitLocked(in: domain)
        }
    }

    nonisolated private static func response(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }

    private final class Clock { var instant = ContinuousClock.now }
    private enum PreparationFault: Error { case blockedParser }
}
#endif
