import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Transit

nonisolated private enum BackupInterruption: CaseIterable, Equatable, Sendable {
    case savedChange, unavailable, cancelled
}

/// Blocks only the worker, allowing deterministic UI-actor changes across the recovery await.
nonisolated private final class PausedBackupExport: Sendable {
    let entered = Mutex(false)
    let usedMainThread = Mutex(false)
    let resume = DispatchSemaphore(value: 0)

    func export(_ archive: DatabaseArchive, to url: URL) throws -> DatabaseArchive {
        usedMainThread.withLock { $0 = Thread.isMainThread }
        let restored = try DatabaseBackupIO.export(archive, to: url)
        entered.withLock { $0 = true }
        guard resume.wait(timeout: .now() + 5) == .success else {
            throw DatabaseBackupError.unavailable
        }
        return restored
    }

    @MainActor func waitUntilEntered() async throws {
        for _ in 0..<400 {
            if entered.withLock({ $0 }) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw DatabaseBackupError.unavailable
    }
}

@MainActor @Suite(.serialized)
struct DatabaseBackupAsyncTests {
    @Test(arguments: ["{\"formatVersion\":", "not JSON"])
    func malformedImportFileCannotChangeStore(_ contents: String) async throws {
        let fixture = try TestModelContainer()
        fixture.context.insert(Project(name: "Keep", description: "", gitRepo: nil, colorHex: "abcdef"))
        try fixture.context.save()
        let service = DatabaseBackupService(container: fixture.container)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(contents.utf8).write(to: url)
        await #expect(throws: (any Error).self) { _ = try await service.readAndVerify(url) }
        let saved = try ModelContext(fixture.container).fetch(FetchDescriptor<Project>())
        #expect(saved.count == 1)
        #expect(saved.first?.name == "Keep")
    }

    @Test func cancelledWipePreservesVerifiedDataset() async throws {
        let fixture = try TestModelContainer()
        fixture.context.insert(Project(name: "Keep", description: "", gitRepo: nil, colorHex: "abcdef"))
        try fixture.context.save()
        let service = DatabaseBackupService(container: fixture.container)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let exported = try await service.export(to: url)
        let operation = Task { try await service.wipe(backupURL: url, confirmation: "WIPE") }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<Project>()) == 1)
        #expect(try DatabaseBackupIO.verify(Data(contentsOf: url)) == exported)
    }

    @Test(arguments: BackupInterruption.allCases)
    private func replacementRechecksAfterBackgroundRecovery(_ interruption: BackupInterruption) async throws {
        let fixture = try TestModelContainer()
        let project = Project(name: "Original", description: "", gitRepo: nil, colorHex: "abcdef")
        fixture.context.insert(project)
        try fixture.context.save()
        let empty = try TestModelContainer()
        let incoming = try DatabaseBackupService(container: empty.container).capture()
        let availability = PersistenceAvailability()
        let pause = PausedBackupExport()
        defer { pause.resume.signal() }
        let service = DatabaseBackupService(
            container: fixture.container, availability: availability,
            writer: DatabaseBackupWriter { try pause.export($0, to: $1) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = directory.appendingPathComponent("recovery.transitbackup")
        let operation = Task { try await service.replace(with: incoming, recoveryURL: recovery) }
        defer { operation.cancel() }
        try await pause.waitUntilEntered()
        #expect(!pause.usedMainThread.withLock { $0 })
        switch interruption {
        case .savedChange:
            project.name = "Changed while exporting"
            try fixture.context.save()
        case .unavailable:
            availability.requireRestartAfterReplacement()
        case .cancelled:
            operation.cancel()
        }
        pause.resume.signal()
        await #expect(throws: (any Error).self) { try await operation.value }
        let saved = try ModelContext(fixture.container).fetch(FetchDescriptor<Project>())
        #expect(saved.count == 1)
        #expect(saved.first?.name == (interruption == .savedChange ? "Changed while exporting" : "Original"))
        let backup = try DatabaseBackupIO.verify(Data(contentsOf: recovery))
        #expect(backup.projectRows.first?.name == "Original")
    }

    @Test func manualPreparationAndReadbackRoundTrip() async throws {
        let fixture = try TestModelContainer()
        let service = DatabaseBackupService(container: fixture.container)
        let prepared = try await service.preparedExport()
        #expect(try DatabaseBackupIO.verify(prepared.data) == prepared.archive)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try prepared.data.write(to: url)
        #expect(try await service.readAndVerify(url, synchronize: true) == prepared.archive)
    }

    @Test func invalidIncomingArchiveCreatesNoRecoveryAndPreservesStore() async throws {
        let fixture = try TestModelContainer()
        fixture.context.insert(Project(name: "Keep", description: "", gitRepo: nil, colorHex: "abcdef"))
        try fixture.context.save()
        let service = DatabaseBackupService(container: fixture.container)
        var invalid = try service.capture()
        invalid.formatVersion = 999
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) { try await service.replace(with: invalid, recoveryURL: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<Project>()) == 1)
    }

    @Test func wipeRejectsFileChangedAfterPreflightVerification() async throws {
        let fixture = try TestModelContainer()
        fixture.context.insert(Project(name: "Keep", description: "", gitRepo: nil, colorHex: "abcdef"))
        try fixture.context.save()
        let service = DatabaseBackupService(container: fixture.container)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = try await service.export(to: url)
        var changedFile = expected
        changedFile.createdAt = expected.createdAt.addingTimeInterval(60)
        try DatabaseBackupIO.encoded(changedFile).write(to: url)
        await #expect(throws: (any Error).self) {
            try await service.wipe(backupURL: url, confirmation: "WIPE", expectedArchive: expected)
        }
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<Project>()) == 1)
    }
}
