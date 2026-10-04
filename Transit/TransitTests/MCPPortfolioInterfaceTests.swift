#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPPortfolioInterfaceTests {
    @Test func realFixtureBindsSharedDTOsAndCanonicalCommentCoveredRevision() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let captured = try fixture.capture()
        #expect(captured.tasks.count == MCPPortfolioFixture.expectedTaskCount)
        #expect(captured.projects.count == 2 && captured.milestones.count == 2)
        #expect(captured.captureScope == .wholePortfolio)
        let model = fixture.tasks[6]
        let record = try #require(captured.tasks.first { $0.id == model.id })
        #expect(record.revision == (try MCPRecordSnapshot.task(model, in: fixture.owner.context).revision))
        #expect(record.commentKeys == captured.comments.map(\.physicalKey))
        #expect(record.requestedCommentRecordsJSON == nil)
        #expect(record.fullRecordWithoutCommentsJSON != nil)
    }

}
#endif
