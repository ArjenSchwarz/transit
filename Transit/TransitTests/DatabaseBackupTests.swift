@preconcurrency import CloudKit
import Foundation
import SwiftData
import Synchronization
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

    @Test func failedRollbackCleanupPreservesOriginalErrorAndSealsWrites() throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let maintenance = DatabaseMaintenanceGate()
        let availability = PersistenceAvailability()
        maintenance.install(container: fixture.container, prepare: { [] }, cancel: {
            throw NSError(domain: "SyntheticCleanup", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "synthetic journal cleanup failed"])
        }, finish: {})
        let service = DatabaseBackupService(
            container: fixture.container, availability: availability, maintenance: maintenance,
            save: { _ in
                throw NSError(domain: "SyntheticSave", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "synthetic database save failed"])
            })
        let before = try service.capture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let exported = try service.export(to: url)
        do {
            try service.wipe(backupURL: url, confirmation: "WIPE")
            Issue.record("Expected failed save and cleanup")
        } catch {
            #expect(error.localizedDescription.contains("synthetic database save failed"))
            #expect(error.localizedDescription.contains("synthetic journal cleanup failed"))
        }
        var after = try DatabaseArchive.capture(ModelContext(fixture.container), now: before.createdAt)
        after.archivedReservationJSON = before.archivedReservationJSON
        #expect(after == before)
        #expect(maintenance.requiresRestart)
        #expect(availability.areWritesUnavailable)
        #expect(throws: (any Error).self) { try service.capture() }
        #expect(try DatabaseBackupIO.verify(Data(contentsOf: url)) == exported)
    }

    @Test func cloudCoverageRejectsUnbackedAndDifferentRecords() throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let archive = try DatabaseBackupService(container: fixture.container).capture()
        let custom = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")
        #expect(try CloudBackupCoverage.transitZones([.default(), custom]).map(\.zoneID) == [custom.zoneID])
        #expect(throws: (any Error).self) {
            try CloudBackupCoverage.transitZones([CKRecordZone(zoneName: "unexpected")])
        }
        let row = try #require(archive.projectRows.first)
        let record = CKRecord(recordType: "CD_Project")
        record["CD_id"] = row.id.uuidString
        record["CD_name"] = row.name
        record["CD_projectDescription"] = row.projectDescription
        record["CD_gitRepo"] = row.gitRepo
        record["CD_colorHex"] = row.colorHex
        try CloudBackupCoverage.verifyRecords([record], archive: archive)
        let duplicate = CKRecord(recordType: "CD_Project")
        for key in record.allKeys() { duplicate[key] = record[key] }
        #expect(throws: (any Error).self) {
            try CloudBackupCoverage.verifyRecords([record, duplicate], archive: archive)
        }
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
        let second = Project(name: "First", description: "", gitRepo: nil, colorHex: "aaa")
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
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        let spring = try #require(formatter.date(from: "2026-03-08T08:00:00Z"))
        #expect(schedule.latestDue(before: spring, calendar: calendar) == formatter.date(from: "2026-03-08T07:00:00Z"))
        let autumn = try #require(formatter.date(from: "2026-11-01T08:00:00Z"))
        #expect(
            BackupSchedule(hour: 1, minute: 30).latestDue(before: autumn, calendar: calendar)
                == formatter.date(from: "2026-11-01T05:30:00Z"))
    }
    @Test func persistentStoreBackupUsesSavedHistoryFence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = DatabaseArchive.schema
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appendingPathComponent("fixture.store"),
            cloudKitDatabase: .none)
        let fixture = try TestModelContainer(schema: schema, configurations: [configuration])
        try populated(fixture)
        let service = DatabaseBackupService(container: fixture.container)
        let archive = try service.capture()
        #expect(try service.decodeAndVerify(service.encoded(archive)) == archive)
    }

}

@MainActor
extension DatabaseBackupTests {
    @Test func backgroundWriterRoundTripsWithoutUsingUIExecutor() async throws {
        let fixture = try TestModelContainer()
        try populated(fixture)
        let archive = try DatabaseBackupService(container: fixture.container).capture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let usedMainThread = Mutex(false)
        let writer = DatabaseBackupWriter { archive, url in
            usedMainThread.withLock { $0 = Thread.isMainThread }
            return try DatabaseBackupIO.export(archive, to: url)
        }
        let url = directory.appendingPathComponent("complete.transitbackup")
        let restored = try await writer.export(archive, to: url)
        #expect(!usedMainThread.withLock { $0 })
        #expect(restored == archive)
        #expect(try DatabaseBackupIO.verify(Data(contentsOf: url)) == archive)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
    }

    @Test func failedVerificationCleansStagingAndPreservesPublishedDestination() throws {
        let fixture = try TestModelContainer()
        let archive = try DatabaseBackupService(container: fixture.container).capture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("complete.transitbackup")
        #expect(throws: (any Error).self) {
            try DatabaseBackupIO.export(archive, to: url, verify: { _ in throw DatabaseBackupError.changed })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let previous = Data("previous recoverable backup".utf8)
        try previous.write(to: url)
        #expect(throws: (any Error).self) {
            try DatabaseBackupIO.export(archive, to: url, verify: { _ in
                var different = archive
                different.createdAt = archive.createdAt.addingTimeInterval(1)
                return different
            })
        }
        #expect(try Data(contentsOf: url) == previous)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
    }

}
