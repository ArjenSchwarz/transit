import Foundation
import Darwin
import Testing

@testable import Transit

@MainActor @Suite(.serialized)
struct BackupStagingFilesTests {
    @Test func listingFailureCannotPreventVerifiedPublication() throws {
        let fixture = try TestModelContainer()
        let archive = try DatabaseBackupService(container: fixture.container).capture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("complete.transitbackup")
        let restored = try DatabaseBackupIO.export(archive, to: url, cleanupStaging: { _ in
            throw CocoaError(.fileReadNoPermission)
        })
        #expect(restored == archive)
        #expect(try DatabaseBackupIO.verify(Data(contentsOf: url)) == archive)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
    }

    @Test func stagingCreationReportsOperatingSystemReason() throws {
        let parentFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parentFile) }
        try Data("synthetic".utf8).write(to: parentFile)
        do {
            _ = try BackupStagingFiles.create(in: parentFile)
            Issue.record("Expected a non-directory parent to refuse creation")
        } catch {
            #expect(error.localizedDescription.contains(String(cString: strerror(ENOTDIR))))
        }
    }

    @Test func sweepRemovesOnlyOldUnlockedRegularTransitStages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date.now
        let old = now.addingTimeInterval(-BackupStagingFiles.staleAfter - 1)
        func file(_ name: String, modified: Date) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try Data("synthetic".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            return url
        }
        let stale = try file(".Transit-" + UUID().uuidString + ".pending", modified: old)
        let young = try file(".Transit-" + UUID().uuidString + ".pending", modified: now)
        let published = try file("Transit-old.transitbackup", modified: old)
        let unknown = try file(".Transit-not-a-uuid.pending", modified: old)
        let link = directory.appendingPathComponent(".Transit-" + UUID().uuidString + ".pending")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: published)
        let folder = directory.appendingPathComponent(".Transit-" + UUID().uuidString + ".pending")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.path)
        let active = try BackupStagingFiles.create(in: directory)
        defer { try? active.handle.close() }
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: active.url.path)
        try BackupStagingFiles.removeStale(in: directory, now: now)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        for url in [young, published, unknown, link, folder, active.url] {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #expect(try Data(contentsOf: published) == Data("synthetic".utf8))
        try active.handle.close()
        try BackupStagingFiles.removeStale(in: directory, now: now)
        #expect(!FileManager.default.fileExists(atPath: active.url.path))
    }

    @Test func nextExportSweepsCrashStageAndPublishesVerifiedBackup() async throws {
        let fixture = try TestModelContainer()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let crashed = directory.appendingPathComponent(".Transit-" + UUID().uuidString + ".pending")
        try Data("incomplete".utf8).write(to: crashed)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-BackupStagingFiles.staleAfter - 10)],
            ofItemAtPath: crashed.path)
        let url = directory.appendingPathComponent("complete.transitbackup")
        let exported = try await DatabaseBackupService(container: fixture.container).export(to: url)
        #expect(try DatabaseBackupIO.verify(Data(contentsOf: url)) == exported)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
    }
}
