#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskConsolidationCaptureBatchTests {
    @Test func savedParticipantDiscoveryBatchesWithoutLoadingUnrelatedPayloads() async throws {
        let fixture = try TaskConsolidationCommitFixture()
        _ = await fixture.execute()
        let owner = try fixture.base.observer()
        let context = owner.context
        let project = try #require(fixture.base.task(fixture.base.source.id, in: context).project)
        var ids: [UUID] = [fixture.base.source.id, fixture.extra.id]
        for index in 0..<260 {
            let task = TransitTask(name: "unrelated \(index)", type: .feature,
                project: project, displayID: .permanent(100 + index))
            context.insert(task)
            ids.append(task.id)
        }
        context.insert(try TaskConsolidationEvent(id: UUID(), operationId: UUID(), kindRawValue: "apply",
            createdAt: Date(), originScopeId: "unrelated", survivorTaskId: UUID(), candidateTaskIds: [],
            payloadJSON: "unrelated malformed payload"))
        try context.save()
        var querySizes: [Int] = []
        let capture = TaskConsolidationSavedCapture(container: fixture.base.owner.container,
            fence: .actorOnlyTestFixture, hooks: .init(participantQuery: { querySizes.append($0) }))
        let evidence = try capture.copy(.init(selectedTaskIds: ids, requireSelectedOriginals: false),
            in: context)
        #expect(querySizes == [128, 128, 6])
        #expect(evidence.events.count == 1 && evidence.history.count == 1)
        #expect(Set(evidence.originals.map(\.id))
            == Set([fixture.base.source.id, fixture.base.target.id, fixture.extra.id]))
        #expect(evidence.encodedByteCount <= 16 * 1_024 * 1_024)
    }
}
#endif
