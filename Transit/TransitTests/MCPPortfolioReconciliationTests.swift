#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

extension MCPPortfolioProjectionTests {
    @Test(arguments: ["idea", "planning", "spec", "ready-for-implementation", "in-progress",
                      "ready-for-review", "done", "abandoned"])
    func everyEffectiveStatusReconcilesAcrossAllPages(status: String) throws {
        let capture = try MCPPortfolioSavedFixture(taskCount: 37).capture()
        let root = try MCPReusableSnapshotStoreTests().bundle(capture).root
        let summary = try PortfolioSummaryService.summarize(view: capture, window: root.window)
        let project = try #require(summary.projects.first { $0.projectId == MCPPortfolioFixture.populatedProjectID })
        let plan = try MCPPortfolioProjection.query(
            root: root, request: query(root, limit: 1, projectId: project.projectId, statuses: [status]))
        let selected = try rows(plan)
        let expected = capture.tasks.filter { $0.effectiveStatus == status }
        #expect(selected.count == expected.count)
        let position = try #require(PortfolioSummaryTestValues.statuses.firstIndex(of: status))
        #expect(selected.count == PortfolioSummaryTestValues.buckets(project.countsByStatus)[position])
        #expect(selected.allSatisfy { $0["status"] as? String == status })
        #expect(selected.compactMap { $0["taskId"] as? String } == expected.map(\.id.uuidString).sorted())
        #expect(plan.pages.count == max(0, selected.count - 1))
        #expect(plan.pages.count == plan.cursors.count && plan.cursors.allSatisfy {
            MCPCursorFamily.classify($0) == .reusable
        })
        #expect(plan.frozenMetadataBytes == root.frozenMetadataBytes)
        #expect(plan.snapshotId == root.capture.metadata.snapshotId)
        #expect(plan.retentionDeadline == root.capture.retentionDeadline)
    }

    @Test func absentAndEmptyFiltersReturnAllRecordsWithDeterministicOrdering() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let reversed = PortfolioSummaryTestValues.view(capture, tasks: Array(capture.tasks.reversed()))
        let root = try MCPReusableSnapshotStoreTests().bundle(reversed).root
        let plan = try MCPPortfolioProjection.query(root: root, request: query(root, limit: 2))
        let selected = try rows(plan)
        #expect(selected.count == capture.tasks.count)
        #expect(selected.compactMap { $0["taskId"] as? String } == capture.tasks.map(\.id.uuidString).sorted())
        let emptyProject = try MCPPortfolioProjection.query(
            root: root, request: query(root, projectId: MCPPortfolioFixture.emptyProjectID))
        #expect(try rows(emptyProject).isEmpty && emptyProject.pages.isEmpty && emptyProject.cursors.isEmpty)
        #expect(try object(emptyProject.firstPage)["nextCursor"] is NSNull)
        #expect(emptyProject.frozenMetadataBytes == plan.frozenMetadataBytes)
    }

    @Test func selectedPhysicalScopeCannotBeExpandedByForeignIdentityClosure() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let foreign = try #require(try fixture.owner.context.fetch(FetchDescriptor<Project>()).first {
            $0.id == MCPPortfolioFixture.emptyProjectID
        })
        let foreignTask = TransitTask(name: "Foreign closure task", type: .feature, project: foreign,
                                      displayID: .permanent(10))
        foreignTask.id = UUID(uuidString: "00000000-0000-4002-8000-000000000001")!
        foreignTask.taskDescription = "Foreign body must remain outside the captured physical scope"
        foreignTask.metadata = ["foreign": "excluded"]
        fixture.owner.context.insert(foreignTask)
        try fixture.owner.context.save()
        let scoped = try MCPReadCaptureBuilder(container: fixture.owner.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: [.id(fixture.project.id)], selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        let selected = try #require(scoped.projects.first { $0.id == fixture.project.id })
        let foreignIdentity = try #require(scoped.tasks.first { $0.id == foreignTask.id })
        #expect(scoped.captureScope == .projects([selected.physicalKey]))
        #expect(scoped.tasks.count == 10)
        #expect(scoped.tasks.filter { $0.projectKey == selected.physicalKey }.count == 9)
        #expect(scoped.tasks.filter { $0.projectKey == selected.physicalKey }.allSatisfy {
            $0.revision != nil && $0.fullRecordWithoutCommentsJSON != nil
        })
        #expect(foreignIdentity.projectKey != selected.physicalKey)
        #expect(foreignIdentity.fullRecordWithoutCommentsJSON == nil && foreignIdentity.revision == nil)
        #expect(foreignIdentity.taskDescription == nil && foreignIdentity.metadata.isEmpty)
        let root = try MCPReusableSnapshotStoreTests().bundle(scoped).root
        let plan = try MCPPortfolioProjection.query(root: root, request: query(root))
        let returned = try rows(plan)
        #expect(returned.count == 9)
        #expect(!returned.contains { $0["taskId"] as? String == foreignTask.id.uuidString })
        #expect(throws: MCPReusableSnapshotError.incompatible) {
            try MCPPortfolioProjection.query(
                root: root, request: query(root, projectId: MCPPortfolioFixture.emptyProjectID))
        }
        #expect(throws: MCPReusableSnapshotError.incompatible) {
            try MCPPortfolioProjection.query(root: root, request: query(root, projectId: UUID()))
        }
        let narrowed = try MCPPortfolioProjection.query(root: root, request: query(root, projectId: selected.id))
        #expect(try rows(narrowed).count == 9)
    }

    @Test func selectedQueryAndMismatchedSnapshotCannotMasqueradeAsReusableQuery() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let helper = MCPReusableSnapshotStoreTests()
        let unsupported = [
            PortfolioSummaryTestValues.view(capture, scope: .selectedQuery),
            PortfolioSummaryTestValues.view(capture, completeness: .selectedRead)
        ]
        for view in unsupported {
            let root = try helper.bundle(view).root
            #expect(throws: MCPReusableSnapshotError.incompatible) {
                try MCPPortfolioProjection.query(root: root, request: query(root))
            }
        }
        let valid = try helper.bundle(capture).root
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try MCPPortfolioProjection.query(root: valid,
                request: .initial(snapshotId: UUID().uuidString, detail: .summary, limit: 2,
                                  projectId: nil, statuses: []))
        }
        #expect(throws: MCPReusableSnapshotError.incompatible) {
            try MCPPortfolioProjection.query(root: valid,
                request: .continuation(cursor: helper.cursorToken(), policy: nil))
        }
    }

    @Test func ambiguousTaskUUIDIntoSelectedScopeFailsWithoutMergingRecords() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let selected = try #require(capture.projects.first { $0.id == MCPPortfolioFixture.populatedProjectID })
        let foreign = try #require(capture.projects.first { $0.id == MCPPortfolioFixture.emptyProjectID })
        let tasks = capture.tasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let duplicate = PortfolioSummaryTestValues.task(tasks[1], id: tasks[0].id,
                                                        projectKey: .some(foreign.physicalKey))
        let changed = PortfolioSummaryTestValues.view(capture, scope: .projects([selected.physicalKey]),
                                                      tasks: [tasks[0], duplicate])
        let root = try MCPReusableSnapshotStoreTests().bundle(changed).root
        #expect(throws: PortfolioSummaryError.identityAmbiguity) {
            try MCPPortfolioProjection.query(root: root, request: query(root))
        }
    }

    @Test func summaryRowsUseNormalizedNameThenUUIDAndMilestonesUseUUID() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let projects = capture.projects.map { PortfolioSummaryTestValues.project($0, name: " Shared ") }
        let changed = PortfolioSummaryTestValues.view(capture, projects: Array(projects.reversed()),
                                                      milestones: Array(capture.milestones.reversed()))
        let summary = try PortfolioSummaryService.summarize(view: changed, window: MCPPortfolioFixture.window)
        #expect(summary.projects.map(\.projectId.uuidString) == projects.map(\.id.uuidString).sorted())
        for project in summary.projects {
            #expect(project.milestones.map(\.milestoneId.uuidString)
                == project.milestones.map(\.milestoneId.uuidString).sorted())
        }
    }

    @Test func ordinaryTaskStatusFiltersKeepStoredStatusSemantics() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let filters = MCPQueryFilters.from(args: ["status": ["idea"]], type: nil,
                                           projectId: nil, search: nil, milestoneIds: nil)
        let ordinary = fixture.tasks.filter { filters.matches($0) }
        #expect(ordinary.count == 1 && ordinary.allSatisfy { $0.statusRawValue == "idea" })
        let capture = try fixture.capture()
        #expect(capture.tasks.filter { $0.effectiveStatus == "idea" }.count == 2)
    }

    @Test func savedMutationDeletionAndNewStoreTransactionCannotChangeRetainedPages() throws {
        let fixture = try MCPPortfolioSavedFixture(taskCount: 19)
        let capture = try fixture.capture()
        let helper = MCPReusableSnapshotStoreTests()
        let candidate = try helper.bundle(capture)
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        try helper.commit(helper.stage(candidate, store: store), in: domain)
        let root = candidate.root
        let before = try MCPPortfolioProjection.query(root: root, request: query(root, detail: .full, limit: 2))
        fixture.project.name = "Changed live project"
        fixture.tasks[0].statusRawValue = "abandoned"
        fixture.tasks[0].taskDescription = "Changed live description"
        fixture.tasks[0].metadata = ["changed": "live"]
        fixture.comment.content = "Changed live comment"
        let deletedID = fixture.tasks[1].id
        fixture.owner.context.delete(fixture.tasks[1])
        try fixture.owner.context.save()
        // A separate committed context models another writer's transaction, not proof of CloudKit import.
        let otherContext = ModelContext(fixture.owner.container)
        let laterProject = Project(name: "Later saved project", description: "", gitRepo: nil, colorHex: "#778899")
        otherContext.insert(laterProject)
        let added = TransitTask(name: "Later saved task", type: .feature, project: laterProject,
                                displayID: .permanent(500))
        otherContext.insert(added)
        try otherContext.save()
        let current = try fixture.capture()
        #expect(current.tasks.contains { $0.id == added.id })
        #expect(!current.tasks.contains { $0.id == deletedID })
        let retained = try store.retainedView(for: root.capture.metadata.snapshotId, now: capture.createdAt)
        let after = try MCPPortfolioProjection.query(root: retained, request: query(retained, detail: .full, limit: 2))
        #expect(NSArray(array: try rows(before)).isEqual(to: try rows(after)))
        #expect(after.frozenMetadataBytes == before.frozenMetadataBytes)
        #expect(after.snapshotId == before.snapshotId && after.retentionDeadline == before.retentionDeadline)
        #expect(retained.window == root.window)
        #expect(try PortfolioSummaryService.summarize(view: retained.capture, window: retained.window)
            == PortfolioSummaryService.summarize(view: root.capture, window: root.window))
        try verifyPublishedPages(after, root: root, store: store, domain: domain, helper: helper)
    }

    private func verifyPublishedPages(_ plan: EncodedSnapshotTaskPages, root: RetainedView,
                                      store: MCPReusableSnapshotStore, domain: MCPReadPublicationDomain,
                                      helper: MCPReusableSnapshotStoreTests) throws {
        let reservation = try store.reserveAppend(snapshotID: plan.snapshotId, pages: plan.pages, cursors: plan.cursors,
                                                   publicationDeadline: root.capture.retentionDeadline)
        try helper.commit(store.prepare(reservation: reservation), in: domain)
        var page = try object(plan.firstPage)
        let expiry = try #require(page["expiresAt"] as? String)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let capturedAt = try #require(formatter.date(from: root.capture.metadata.asOf))
        let pageExpiry = formatter.date(from: expiry) ?? ISO8601DateFormatter().date(from: expiry)
        #expect(pageExpiry == capturedAt.addingTimeInterval(300))
        var allRows = try #require(page["results"] as? [[String: Any]])
        var visited: Set<String> = []
        while let cursor = page["nextCursor"] as? String {
            #expect(visited.insert(cursor).inserted)
            let retained = try store.page(for: cursor, now: root.capture.createdAt)
            #expect(retained.root.frozenMetadataBytes == root.frozenMetadataBytes)
            #expect(retained.root.window == root.window)
            #expect(retained.root.capture.retentionDeadline == root.capture.retentionDeadline)
            page = try object(retained.encodedPage)
            #expect(page["expiresAt"] as? String == expiry)
            allRows += try #require(page["results"] as? [[String: Any]])
        }
        #expect(page["nextCursor"] is NSNull && allRows.count == root.capture.tasks.count)
        domain.setTestingInstant(root.capture.retentionDeadline)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.retainedView(for: plan.snapshotId, now: root.capture.retentionDeadline)
        }
        for cursor in plan.cursors {
            #expect(throws: MCPReusableSnapshotError.invalidCursor) {
                try store.page(for: cursor, now: root.capture.retentionDeadline)
            }
        }
    }
}
#endif
