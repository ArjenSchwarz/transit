import Foundation
import Testing

@testable import Transit

@MainActor @Suite(.serialized)
struct BackupSchedulerTests {
    @Test func missingFolderIsObservableAndBackedOff() async throws {
        let fixture = try TestModelContainer()
        let domain = "TransitBackupTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let now = Date.now
        defaults.set(true, forKey: "backup.scheduleEnabled")
        defaults.set(now.addingTimeInterval(-172800), forKey: "backup.enabledAt")
        let scheduler = BackupScheduler(
            service: DatabaseBackupService(container: fixture.container), defaults: defaults)
        await scheduler.check(now: now)
        #expect(scheduler.lastError != nil)
        #expect(scheduler.lastError == defaults.string(forKey: "backup.lastError"))
        #expect(defaults.object(forKey: "backup.nextAttempt") as? Date == now.addingTimeInterval(3600))
        await scheduler.check(now: now.addingTimeInterval(60))
        #expect(defaults.object(forKey: "backup.nextAttempt") as? Date == now.addingTimeInterval(3600))
        #expect(scheduler.lastSuccess == nil)
    }

    @Test func exportFailureThenRecoveryRenewsFolderAndClosesAccess() async throws {
        let fixture = try TestModelContainer()
        let domain = "TransitBackupTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let now = Date.now
        defaults.set(true, forKey: "backup.scheduleEnabled")
        defaults.set(now.addingTimeInterval(-172800), forKey: "backup.enabledAt")
        defaults.set(Data([1]), forKey: "backup.directoryBookmark")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var closed = 0
        let access: @MainActor (Data) throws -> BackupDirectoryAccess = { _ in
            BackupDirectoryAccess(url: directory, renewedBookmark: Data([2]), close: { closed += 1 })
        }
        let failing = BackupScheduler(
            service: DatabaseBackupService(container: fixture.container), defaults: defaults,
            writer: DatabaseBackupWriter { _, _ in throw DatabaseBackupError.changed }, openDirectory: access)
        await failing.check(now: now)
        #expect(closed == 1)
        #expect(failing.lastError != nil)
        #expect(failing.lastSuccess == nil)
        #expect(defaults.object(forKey: "backup.lastSuccess") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(defaults.data(forKey: "backup.directoryBookmark") == Data([2]))
        let recovered = BackupScheduler(
            service: DatabaseBackupService(container: fixture.container), defaults: defaults,
            openDirectory: access)
        #expect(recovered.lastError == failing.lastError)
        await recovered.check(now: now.addingTimeInterval(60))
        #expect(closed == 1)
        let retry = now.addingTimeInterval(3600)
        await recovered.check(now: retry)
        #expect(closed == 2)
        #expect(recovered.lastSuccess == retry)
        #expect(recovered.lastError == nil)
        #expect(defaults.object(forKey: "backup.nextAttempt") == nil)
        #expect(defaults.string(forKey: "backup.lastError") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    }
}
