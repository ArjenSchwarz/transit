@preconcurrency import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Transit

@MainActor @Suite(.serialized)
struct DatabaseBackupTests {
    private func populated(_ fixture: TestModelContainer) throws {
        let context = fixture.context
        let project = Project(
            name: "Synthetic", description: "all fields", gitRepo: "https://example.invalid/repo",
            colorHex: "abcdef")
        context.insert(project)
        let milestone = Milestone(
            name: "One", description: "raw", project: project, displayID: .permanent(9))
        milestone.statusRawValue = "future-status"
        context.insert(milestone)
        let task = TransitTask(
            name: "Task", type: .feature, project: project, displayID: .permanent(42))
        task.milestone = milestone
        task.priorityRawValue = "future-priority"
        task.metadataJSON = "{malformed preserved}"
        task.completionDate = Date(timeIntervalSince1970: 1234)
        context.insert(task)
        let orphan = TransitTask(name: "Orphan", type: .bug, project: project, displayID: .provisional)
        orphan.project = nil
        context.insert(orphan)
        context.insert(
            Comment(content: "all comments", authorName: "Synthetic", isAgent: true, task: task))
        context.insert(SyncHeartbeat())
        let receipt = MCPWriteReceipt(
            localScopeID: "synthetic", tool: "create_task", key: "key", requestJSON: "raw",
            acceptedAt: .now)
        receipt.resultJSON = "{raw}"
        receipt.resultIsError = false
        context.insert(receipt)
        let edgeID = UUID()
        context.insert(
            TaskLinkOccurrence(
                id: edgeID, kindRawValue: "future-kind", sourceTaskID: task.id, targetTaskID: UUID(),
                createdAt: .now))
        context.insert(
            TaskLinkRemovalEvidence(
                id: UUID(), edgeId: edgeID, kindRawValue: "blocks", sourceTaskID: task.id,
                targetTaskID: orphan.id, createdAt: .now, occurrenceRevision: "l1:raw", removedAt: .now))
        context.insert(
            try TaskConsolidationEvent(
                id: UUID(), operationId: UUID(), kindRawValue: "unknown", createdAt: .now,
                originScopeId: "synthetic", survivorTaskId: task.id, candidateTaskIds: [],
                payloadJSON: "malformed retained", archivedCandidateSlots: [nil, orphan.id, nil, nil, nil]))
        try context.save()
    }

    @Test func fullDatabaseRoundTripAndReplace() throws {
        let source = try TestModelContainer()
        try populated(source)
        let service = DatabaseBackupService(container: source.container)
        let archive = try service.capture()
        let verified = try service.decodeAndVerify(service.encoded(archive))
        #expect(verified == archive)
        #expect(archive.taskConsolidationEventRows.first?.candidate1 == nil)
        #expect(archive.taskConsolidationEventRows.first?.candidate2 != nil)
        let target = try TestModelContainer()
        let recovery = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: recovery) }
        let destination = DatabaseBackupService(container: target.container)
        try destination.replace(with: verified, recoveryURL: recovery)
        let result = try DatabaseArchive.capture(ModelContext(target.container), now: archive.createdAt)
        #expect(result == archive)
        #expect(FileManager.default.fileExists(atPath: recovery.path))
    }

    @Test func invalidRelationshipAndVersionAreRejected() throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let service = DatabaseBackupService(container: fixture.container)
        var archive = try service.capture()
        archive.transitTaskRows[0].projectRow = 999
        #expect(throws: (any Error).self) { try service.decodeAndVerify(service.encoded(archive)) }
        archive = try service.capture()
        archive.formatVersion = 99
        #expect(throws: (any Error).self) { try service.decodeAndVerify(service.encoded(archive)) }
        #expect(try fixture.context.fetchCount(FetchDescriptor<TransitTask>()) == 2)
    }

    @Test func wipeRequiresConfirmationAndUnchangedVerifiedFile() throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let service = DatabaseBackupService(container: fixture.container)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try service.export(to: url)
        #expect(throws: (any Error).self) { try service.wipe(backupURL: url, confirmation: "") }
        let task = try #require(fixture.context.fetch(FetchDescriptor<TransitTask>()).first)
        task.name = "Changed"
        try fixture.context.save()
        #expect(throws: (any Error).self) { try service.wipe(backupURL: url, confirmation: "WIPE") }
        _ = try service.export(to: url)
        try service.wipe(backupURL: url, confirmation: "WIPE")
        #expect(try fixture.context.fetchCount(FetchDescriptor<Project>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TransitTask>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0)
        _ = try service.decodeAndVerify(Data(contentsOf: url))
    }

    @Test func saveFailurePreservesAllOriginalData() throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let service = DatabaseBackupService(container: fixture.container)
        let before = try service.capture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try service.export(to: url)
        let failing = DatabaseBackupService(
            container: fixture.container, save: { _ in throw DatabaseBackupError.unavailable })
        #expect(throws: (any Error).self) { try failing.wipe(backupURL: url, confirmation: "WIPE") }
        let after = try DatabaseArchive.capture(ModelContext(fixture.container), now: before.createdAt)
        #expect(after == before)
        #expect(throws: (any Error).self) { try failing.replace(with: before, recoveryURL: url) }
        #expect(
            try DatabaseArchive.capture(ModelContext(fixture.container), now: before.createdAt) == before)
    }

    @Test func cloudCoverageRejectsUnbackedAndDifferentRecords() throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let archive = try DatabaseBackupService(container: fixture.container).capture()
        let row = try #require(archive.projectRows.first)
        let record = CKRecord(recordType: "CD_Project")
        record["CD_id"] = row.id.uuidString
        record["CD_name"] = row.name
        record["CD_projectDescription"] = row.projectDescription
        record["CD_gitRepo"] = row.gitRepo
        record["CD_colorHex"] = row.colorHex
        try CloudBackupCoverage.verifyRecords([record], archive: archive)
        record["CD_name"] = "Remote edit"
        #expect(throws: (any Error).self) { try CloudBackupCoverage.verifyRecords([record], archive: archive) }
        record["CD_id"] = UUID().uuidString
        #expect(throws: (any Error).self) { try CloudBackupCoverage.verifyRecords([record], archive: archive) }
        let unknown = CKRecord(recordType: "FutureEntity")
        #expect(throws: (any Error).self) { try CloudBackupCoverage.verifyRecords([unknown], archive: archive) }
    }

    @Test func duplicateUUIDsRetainPhysicalRelationshipTargets() throws {
        let fixture = try TestModelContainer()
        let first = Project(name: "First", description: "", gitRepo: nil, colorHex: "aaa")
        let second = Project(name: "Second", description: "", gitRepo: nil, colorHex: "bbb")
        second.id = first.id
        fixture.context.insert(first)
        fixture.context.insert(second)
        fixture.context.insert(TransitTask(name: "One", type: .feature, project: first, displayID: .permanent(1)))
        fixture.context.insert(TransitTask(name: "Two", type: .bug, project: second, displayID: .permanent(2)))
        try fixture.context.save()
        let service = DatabaseBackupService(container: fixture.container)
        let archive = try service.capture()
        #expect(try service.decodeAndVerify(service.encoded(archive)) == archive)
        #expect(throws: (any Error).self) { try archive.cloudRows() }
    }

    #if os(macOS)
    @Test func scheduleUsesLocalTimeAndOneCatchUp() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 1)))
        let late = start.addingTimeInterval(4 * 3600)
        let schedule = BackupSchedule(hour: 2, minute: 0)
        #expect(!schedule.isDue(now: start, lastSuccess: nil, enabledAt: start, calendar: calendar))
        #expect(schedule.isDue(now: late, lastSuccess: nil, enabledAt: start, calendar: calendar))
        #expect(!schedule.isDue(now: late, lastSuccess: late, enabledAt: start, calendar: calendar))
    }
    #endif
}
