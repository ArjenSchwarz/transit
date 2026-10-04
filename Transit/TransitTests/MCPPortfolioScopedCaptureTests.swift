#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPPortfolioScopedCaptureTests {
    @Test func scopedCaptureDoesNotExpandToUnrelatedTaskBodies() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let foreign = try #require(try fixture.owner.context.fetch(FetchDescriptor<Project>()).first {
            $0.id == MCPPortfolioFixture.emptyProjectID
        })
        let unrelated = TransitTask(name: "Unrelated body", type: .feature, project: foreign,
                                    displayID: .permanent(10))
        unrelated.taskDescription = "Must not be copied for another project's scoped capture"
        fixture.owner.context.insert(unrelated)
        try fixture.owner.context.save()
        let view = try MCPReadCaptureBuilder(container: fixture.owner.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: [.id(fixture.project.id)], selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        let selectedKey = try #require(view.projects.first { $0.id == fixture.project.id }?.physicalKey)
        #expect(view.captureScope == .projects([selectedKey]))
        // Identity closure may include endpoint identities; it cannot require a full
        // unrelated task body or revision for this declared scope.
        #expect(!view.tasks.contains { $0.id == unrelated.id && $0.fullRecordWithoutCommentsJSON != nil })
        #expect(view.tasks.filter { $0.projectKey == selectedKey }.count == 9)
        #expect(view.tasks.filter { $0.projectKey == selectedKey }.allSatisfy { $0.revision != nil })
        let identity = try #require(view.tasks.first { $0.id == unrelated.id })
        #expect(identity.revision == nil && identity.taskDescription == nil && identity.metadata.isEmpty)

        let prepared = try MCPPortfolioFoundationHarness.prepareCapture(view)
        let envelope = try #require(
            try JSONSerialization.jsonObject(with: prepared.encodedResponse) as? [String: Any])
        let records = try #require(envelope["records"] as? [String])
        #expect(envelope["taskCount"] as? Int == 9)
        #expect(records.count == 9)
        let evidence = try #require(envelope["taskEvidence"] as? [[String: Any]])
        #expect(evidence.count == 10)
        let foreignEvidence = try #require(evidence.first { $0["id"] as? String == unrelated.id.uuidString })
        #expect(foreignEvidence["revision"] == nil)
        #expect(envelope["snapshotId"] as? String == view.metadata.snapshotId)
        for encoded in records {
            let data = try #require(Data(base64Encoded: encoded))
            let task = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(task["taskId"] as? String != unrelated.id.uuidString)
        }
    }
}
#endif
