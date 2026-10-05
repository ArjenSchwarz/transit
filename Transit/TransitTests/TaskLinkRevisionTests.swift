#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkRevisionTests {
    @Test func emptyIncidenceTransitionsEveryCurrentTaskToken() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let context = fixture.owner.context
        context.delete(fixture.edge)
        try context.save()
        let current = try MCPRecordSnapshot.task(fixture.source, in: context)
        let oldFields = current.coveredFields.filter { $0.key != "linkContract" && $0.key != "incidentLinks" }
        let oldToken = try MCPRecordRevision.token(entity: "task", fields: oldFields)
        #expect(current.revision != oldToken)
        #expect(current.coveredFields["linkContract"] as? String == "task-links-v1")
        #expect((current.coveredFields["incidentLinks"] as? [[String: Any]])?.isEmpty == true)
        #expect(current.record["revisionCoverage"] as? String == "task-fields-comments-links-v1")
        #expect(current.record["graphCoverage"] as? String == "available")
    }

    @Test(arguments: ["incoming", "outgoing"])
    func incidenceAloneChangesBothEndpointTokens(direction: String) throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let context = fixture.owner.context
        let source = try MCPRecordSnapshot.task(fixture.source, in: context).revision
        let target = try MCPRecordSnapshot.task(fixture.target, in: context).revision
        let row = TaskLinkOccurrence(id: UUID(), kindRawValue: "attribution",
            sourceTaskID: direction == "outgoing" ? fixture.source.id : fixture.target.id,
            targetTaskID: direction == "outgoing" ? fixture.target.id : fixture.source.id, createdAt: fixture.instant)
        context.insert(row)
        try context.save()
        #expect(try MCPRecordSnapshot.task(fixture.source, in: context).revision != source)
        #expect(try MCPRecordSnapshot.task(fixture.target, in: context).revision != target)
    }

    @Test func physicalMultiplicityAndMalformedRawTupleCannotDisappearFromToken() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let context = fixture.owner.context
        let baseline = try MCPRecordSnapshot.task(fixture.source, in: context).revision
        let copy = TaskLinkOccurrence(id: fixture.edge.id, kindRawValue: fixture.edge.kindRawValue,
            sourceTaskID: fixture.edge.sourceTaskID, targetTaskID: fixture.edge.targetTaskID,
            createdAt: fixture.edge.createdAt)
        context.insert(copy)
        try context.save()
        #expect(try MCPRecordSnapshot.task(fixture.source, in: context).revision != baseline)
        context.delete(copy)
        try context.save()
        #expect(try MCPRecordSnapshot.task(fixture.source, in: context).revision == baseline)
        let rawId = fixture.edge.id
        context.delete(fixture.edge)
        context.insert(TaskLinkOccurrence(id: rawId, kindRawValue: "future-kind", sourceTaskID: fixture.source.id,
                                         targetTaskID: fixture.target.id, createdAt: fixture.instant))
        try context.save()
        #expect(try MCPRecordSnapshot.task(fixture.source, in: context).revision != baseline)
    }

    @Test func endpointLabelsAndRemovalExpiryDoNotChangeActiveContentToken() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let context = fixture.owner.context
        let token = try MCPRecordSnapshot.task(fixture.source, in: context).revision
        fixture.target.name = "new saved label"
        fixture.target.status = .abandoned
        context.insert(TaskLinkRemovalEvidence(id: UUID(), edgeId: fixture.edge.id,
            kindRawValue: fixture.edge.kindRawValue, sourceTaskID: fixture.edge.sourceTaskID,
            targetTaskID: fixture.edge.targetTaskID, createdAt: fixture.edge.createdAt,
            occurrenceRevision: "raw preserved invalid evidence", removedAt: fixture.instant))
        try context.save()
        #expect(try MCPRecordSnapshot.task(fixture.source, in: context).revision == token)
    }

    @Test func fullCapturedTokenStillCoversLinksWhenBodiesAreOmitted() throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let view = try MCPReadCaptureBuilder(container: fixture.owner.container, fence: .actorOnlyTestFixture).capture(
            ReadCaptureRequest(projectSelectors: nil, selection: .portfolio, completeness: .completePortfolio,
                               includeComments: false))
        let task = try #require(view.tasks.first { $0.id == fixture.source.id })
        let bytes = try #require(task.fullRecordWithoutCommentsJSON)
        let record = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(record["revisionCoverage"] as? String == "task-fields-comments-links-v1")
        #expect(record["graphCoverage"] as? String == "available")
        #expect(record["comments"] == nil)
        #expect(task.revision == (try MCPRecordSnapshot.task(fixture.source, in: fixture.owner.context).revision))
    }

    @Test func retainedReceiptReplayStaysByteIdenticalAfterIncidenceChanges() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        let coordinator = fixture.coordinator(save: { context, _ in try context.save() })
        let arguments = try fixture.updateArguments()
        let first = await coordinator.execute(tool: "update_task", arguments: arguments)
        #expect(try fixture.decode(first)["outcome"] as? String == "committed")
        fixture.owner.context.insert(TaskLinkOccurrence(id: UUID(), kindRawValue: "association",
            sourceTaskID: fixture.source.id, targetTaskID: fixture.target.id, createdAt: fixture.instant))
        try fixture.owner.context.save()
        let replay = await coordinator.execute(tool: "update_task", arguments: arguments)
        #expect(first.content.first?.text == replay.content.first?.text)
        let observer = try fixture.observer()
        #expect(try fixture.historicReceipt(in: observer.context).resultJSON == fixture.historicJSON)
        #expect(try fixture.historicReceipt(in: observer.context).requestJSON == fixture.historicRequest)
    }
}
#endif
