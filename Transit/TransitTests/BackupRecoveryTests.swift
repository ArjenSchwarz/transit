import Foundation
import SwiftData
import Testing

@testable import Transit

@MainActor @Suite(.serialized)
struct BackupRecoveryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func listingExposesOnlyOwnedRegularRecoveryFiles() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owned = directory.appendingPathComponent("BeforeImport-\(UUID()).transitbackup")
        let wipe = directory.appendingPathComponent("BeforeWipe-\(UUID()).transitbackup")
        try Data().write(to: owned)
        try Data().write(to: wipe)
        try Data().write(to: directory.appendingPathComponent("private.json"))
        try Data().write(to: directory.appendingPathComponent("BeforeImport-invalid.transitbackup"))
        let link = directory.appendingPathComponent("BeforeImport-\(UUID()).transitbackup")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: owned)
        let subfolder = directory.appendingPathComponent("BeforeWipe-\(UUID()).transitbackup")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: false)
        #expect(Set(try BackupRecoveryFiles.available(in: directory)) == Set([owned, wipe]))
        #expect(try BackupRecoveryFiles.available(in: directory.appendingPathComponent("absent")).isEmpty)
    }

    @Test func selectedDocumentReadbackUsesDurablePrivateRecoveryAndRejectsChangedCopy() async throws {
        let fixture = try TestModelContainer()
        let service = DatabaseBackupService(container: fixture.container)
        let prepared = try await service.preparedExport()
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = directory.appendingPathComponent("provider")
        try FileManager.default.createDirectory(at: provider, withIntermediateDirectories: false)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: provider.path) }
        let selected = provider.appendingPathComponent("provider-document")
        let recovery = directory.appendingPathComponent("private-recovery")
        try prepared.data.write(to: selected)
        // A granted document remains readable even when its parent cannot be opened for flushing.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: selected.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o100], ofItemAtPath: provider.path)
        do {
            try DurableBackupFile.synchronize(selected)
            Issue.record("Expected denied parent-directory durability check")
        } catch { #expect(error.localizedDescription.contains("backup folder could not be opened")) }
        try await service.retainWipeRecovery(selectedURL: selected, expected: prepared.archive, recoveryURL: recovery)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: provider.path)
        let writer = DatabaseBackupWriter()
        #expect(try await writer.verifiedFileData(recovery) == prepared.data)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: selected.path)
        try Data("bad provider copy".utf8).write(to: selected)
        await #expect(throws: (any Error).self) {
            try await service.retainWipeRecovery(selectedURL: selected, expected: prepared.archive,
                                               recoveryURL: directory.appendingPathComponent("rejected"))
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("rejected").path))
        #expect(try await writer.verifiedFileData(recovery) == prepared.data)
    }

    @Test func durableRecoveryFailureCannotAuthorizeWipe() async throws {
        let fixture = try TestModelContainer()
        fixture.context.insert(Project(name: "Keep", description: "", gitRepo: nil, colorHex: "aaa"))
        try fixture.context.save()
        let service = DatabaseBackupService(container: fixture.container)
        let prepared = try await service.preparedExport()
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selected = directory.appendingPathComponent("selected")
        try prepared.data.write(to: selected)
        let failing = DatabaseBackupService(container: fixture.container,
            writer: DatabaseBackupWriter { _, _ in throw DatabaseBackupError.unavailable })
        let recovery = directory.appendingPathComponent("missing")
        await #expect(throws: (any Error).self) {
            try await failing.retainWipeRecovery(
                selectedURL: selected, expected: prepared.archive, recoveryURL: recovery)
        }
        await #expect(throws: (any Error).self) {
            try await service.wipe(backupURL: recovery, confirmation: "WIPE")
        }
        #expect(try ModelContext(fixture.container).fetchCount(FetchDescriptor<Project>()) == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedSyntheticImportReportsCompletionAndKeepsRecoveryInteractive() async throws {
        let source = try TestModelContainer()
        let project = Project(name: "Synthetic", description: "", gitRepo: nil, colorHex: "aaa")
        source.context.insert(project)
        for index in 0..<300 {
            source.context.insert(TransitTask(name: "Synthetic \(index)", type: .feature,
                                             project: project, displayID: .permanent(index + 1)))
        }
        try source.context.save()
        let archive = try DatabaseBackupService(container: source.container).capture()
        let target = try TestModelContainer()
        let gate = DatabaseMaintenanceGate()
        let availability = PersistenceAvailability()
        gate.install(container: target.container, prepare: { [] }, finish: {})
        let service = DatabaseBackupService(container: target.container, availability: availability, maintenance: gate)
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = directory.appendingPathComponent("recovery")
        var stages: [DatabaseBackupService.ImportStage] = []
        var applyStarted = Date.now
        try await service.replace(with: archive, recoveryURL: recovery) { stage in
            stages.append(stage)
            if stage == .applyingRecords { applyStarted = .now }
        }
        print("Synthetic 300-task final apply seconds: \(Date.now.timeIntervalSince(applyStarted))")
        #expect(stages == [.verifyingBackup, .creatingRecovery, .applyingRecords, .completed])
        #expect(gate.requiresRestart && gate.replacementCommitted)
        #expect(gate.recoveryBackupURL == recovery)
        #expect(availability.areWritesUnavailable)
        #expect(!target.container.mainContext.autosaveEnabled)
        #expect(throws: (any Error).self) { try gate.requireMutationAvailable(in: target.container) }
        #expect(try ModelContext(target.container).fetchCount(FetchDescriptor<TransitTask>()) == 300)
        _ = try await DatabaseBackupWriter().verifiedFileData(recovery)
    }

    @Test func failedSaveDoesNotReportCompletionAndRetainsReadableRecovery() async throws {
        let fixture = try TestModelContainer()
        let gate = DatabaseMaintenanceGate()
        gate.install(container: fixture.container, prepare: { [] }, cancel: {
            throw DatabaseBackupError.unavailable
        }, finish: {})
        let service = DatabaseBackupService(container: fixture.container, availability: PersistenceAvailability(),
                                           maintenance: gate, save: { _ in throw DatabaseBackupError.unavailable })
        let archive = try service.capture()
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = directory.appendingPathComponent("recovery")
        var stages: [DatabaseBackupService.ImportStage] = []
        await #expect(throws: (any Error).self) {
            try await service.replace(with: archive, recoveryURL: recovery) { stages.append($0) }
        }
        #expect(!stages.contains(.completed))
        #expect(gate.requiresRestart && !gate.replacementCommitted)
        #expect(gate.recoveryBackupURL == recovery)
        _ = try await DatabaseBackupWriter().verifiedFileData(recovery)
    }
}
