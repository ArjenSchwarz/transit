#if os(macOS)
import Foundation
import Testing
@testable import Transit

extension MCPReusableSnapshotStoreTests {
    @Test func pinnedRootSurvivesUnrelatedCreateBeforeReturn() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let original = try bundle(capture)
        let unrelated = try bundle(capture)
        try commit(stage(original, store: store), in: domain)
        let root = try store.retainedView(for: original.root.capture.metadata.snapshotId, now: capture.createdAt,
            testingAfterPin: { try commit(stage(unrelated, store: store), in: domain) })
        #expect(root.capture.metadata.snapshotId == original.root.capture.metadata.snapshotId)
        #expect(try metadataBytes(root) == metadataBytes(original.root))
        #expect(try store.view(for: unrelated.root.capture.metadata.snapshotId, now: capture.createdAt)
            .metadata.snapshotId == unrelated.root.capture.metadata.snapshotId)
    }

    @Test func pinnedPageSurvivesSameRootAppendBeforeReturn() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let originalCursor = cursorToken()
        let original = try bundle(capture, pages: [Data([1, 2])], cursors: [originalCursor])
        try commit(stage(original, store: store), in: domain)
        let addedCursor = cursorToken()
        let page = try store.page(for: originalCursor, now: capture.createdAt, testingAfterPin: {
            let reservation = try store.reserveAppend(snapshotID: original.root.capture.metadata.snapshotId,
                pages: [Data([3])], cursors: [addedCursor], publicationDeadline: capture.retentionDeadline)
            try commit(store.prepare(reservation: reservation), in: domain)
        })
        #expect(page.encodedPage == Data([1, 2]))
        #expect(try metadataBytes(page.root) == metadataBytes(original.root))
        #expect(try store.page(for: addedCursor, now: capture.createdAt).encodedPage == Data([3]))
    }

    @Test func pinnedLookupsRejectLifecycleInvalidationBeforeReturn() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let original = try bundle(capture)
        try commit(stage(original, store: store), in: domain)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.retainedView(for: original.root.capture.metadata.snapshotId, now: capture.createdAt,
                                  testingAfterPin: { try store.invalidate() })
        }
        let cursor = cursorToken()
        let replacement = try bundle(capture, pages: [Data([1])], cursors: [cursor])
        try commit(stage(replacement, store: store), in: domain)
        #expect(throws: MCPReusableSnapshotError.invalidCursor) {
            try store.page(for: cursor, now: capture.createdAt, testingAfterPin: { try store.invalidate() })
        }
    }

    @Test(arguments: [false, true])
    func pinnedLookupsRejectRecreatedRootIdentity(pageLookup: Bool) throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let cursor = cursorToken()
        let original = try bundle(capture, pages: [Data([1])], cursors: [cursor])
        let replacement = try bundle(capture, id: original.root.capture.metadata.snapshotId,
                                 pages: [Data([9])], cursors: [cursor])
        try commit(stage(original, store: store), in: domain)
        let replace = {
            try store.invalidate()
            try commit(stage(replacement, store: store), in: domain)
        }
        if pageLookup {
            #expect(throws: MCPReusableSnapshotError.invalidCursor) {
                try store.page(for: cursor, now: capture.createdAt, testingAfterPin: replace)
            }
        } else {
            #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
                try store.retainedView(for: original.root.capture.metadata.snapshotId, now: capture.createdAt,
                                      testingAfterPin: replace)
            }
        }
        #expect(try store.page(for: cursor, now: capture.createdAt).encodedPage == Data([9]))
    }

    @Test(arguments: [false, true])
    func pinnedLookupsRejectExpiryBeforeReturn(pageLookup: Bool) throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let cursor = cursorToken()
        let original = try bundle(capture, pages: [Data([1])], cursors: [cursor])
        try commit(stage(original, store: store), in: domain)
        if pageLookup {
            #expect(throws: MCPReusableSnapshotError.invalidCursor) {
                try store.page(for: cursor, now: capture.createdAt,
                    testingAfterPin: { domain.setTestingInstant(capture.retentionDeadline) })
            }
        } else {
            #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
                try store.retainedView(for: original.root.capture.metadata.snapshotId, now: capture.createdAt,
                    testingAfterPin: { domain.setTestingInstant(capture.retentionDeadline) })
            }
        }
    }
}
#endif
