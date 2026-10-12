import Foundation
import Observation
import OSLog
import SwiftData

/// All mutation uses an owned context. Validation never touches the installed store.
@MainActor @Observable
final class DatabaseBackupService {
    enum ImportStage: Equatable {
        case verifyingBackup, creatingRecovery, applyingRecords, completed

        var title: String {
            switch self {
            case .verifyingBackup: "Checking the selected backup…"
            case .creatingRecovery: "Saving and verifying a recovery backup…"
            case .applyingRecords: "Applying records… This step may briefly pause the screen."
            case .completed: "Import complete. Restart required."
            }
        }
    }
    private static let logger = Logger(subsystem: "me.nore.ig.Transit", category: "Backups")
    let container: ModelContainer
    private let maintenance: DatabaseMaintenanceGate
    private let availability: PersistenceAvailability
    private let save: (ModelContext) throws -> Void
    private let writer: DatabaseBackupWriter

    init(
        container: ModelContainer, availability: PersistenceAvailability = .shared,
        maintenance: DatabaseMaintenanceGate = .shared,
        writer: DatabaseBackupWriter = DatabaseBackupWriter(),
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.availability = availability
        self.maintenance = maintenance
        self.save = save
        self.writer = writer
    }

    func capture() throws -> DatabaseArchive {
        try requireStorage()
        var archive = try DatabaseArchive.capture(ModelContext(container))
        archive.archivedReservationJSON = try maintenance.reservationSnapshot(for: container)
        return archive
    }

    func export(to url: URL) async throws -> DatabaseArchive {
        try await writer.export(capture(), to: url)
    }

    func preparedExport() async throws -> (archive: DatabaseArchive, data: Data) {
        let archive = try capture()
        return (archive, try await writer.preparedData(for: archive))
    }

    func readAndVerify(_ url: URL, synchronize: Bool = false) async throws -> DatabaseArchive {
        try await writer.readAndVerify(url, synchronize: synchronize)
    }

    /// A picker document is readable authority, not permission to flush its parent directory.
    /// Wipe relies on this separately durable app-owned copy, never provider upload guarantees.
    func retainWipeRecovery(selectedURL: URL, expected: DatabaseArchive, recoveryURL: URL) async throws {
        try requireStorage()
        guard try await writer.readAndVerify(selectedURL) == expected else {
            throw DatabaseBackupError.changed
        }
        _ = try await writer.export(expected, to: recoveryURL)
    }

    /// Replace semantics are deliberate: no deduplication, ID allocation or raw-value normalization.
    /// A fresh recovery archive must already exist outside the database at the selected destination.
    func replace(with archive: DatabaseArchive, recoveryURL: URL,
                 progress: (ImportStage) -> Void = { _ in }) async throws {
        try requireStorage()
        progress(.verifyingBackup)
        _ = try await writer.preparedData(for: archive)
        progress(.creatingRecovery)
        let before = try capture()
        _ = try await writer.export(before, to: recoveryURL)
        progress(.applyingRecords)
        // Give the stage label a rendering opportunity; all mutation gates run after this yield.
        await Task.yield()
        try commitReplacement(before: before, incoming: archive, recoveryURL: recoveryURL)
        progress(.completed)
    }

    /// The exact archive read back from disk authorizes only its unchanged saved dataset.
    func wipe(backupURL: URL, confirmation: String, expectedArchive: DatabaseArchive? = nil) async throws {
        guard confirmation == "WIPE" else { throw DatabaseBackupError.confirmationRequired }
        try requireStorage()
        let archive = try await writer.readAndVerify(backupURL)
        if let expectedArchive, expectedArchive != archive { throw DatabaseBackupError.changed }
        try commitReplacement(before: archive, incoming: nil, recoveryURL: backupURL)
    }

    /// Re-check every gate after worker suspension; no await occurs during the final mutation.
    private func commitReplacement(before: DatabaseArchive, incoming: DatabaseArchive?, recoveryURL: URL) throws {
        try Task.checkCancellation()
        try requireStorage()
        try maintenance.requireMutationAvailable(in: container)
        try requireUnchanged(before)
        try maintenance.authorizeReplacement(of: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try DatabaseArchive.deleteAll(in: context)
            if let incoming { _ = try incoming.insert(into: context) }
            try save(context)
        } catch {
            try rollback(context, original: error, recoveryURL: recoveryURL)
        }
        do {
            try maintenance.didReplace(container, availability: availability, recoveryBackupURL: recoveryURL)
        } catch {
            throw DatabaseBackupError.cleanupAfterCommit
        }
    }

    private func rollback(_ context: ModelContext, original: any Error, recoveryURL: URL) throws -> Never {
        // This owned failed context is discarded; no registered model escapes to a cached editor.
        context.rollback()
        do {
            try maintenance.cancelReplacement(of: container)
        } catch {
            // A retry journal with uncertain cleanup must not accept more edits before restart.
            do {
                try maintenance.didReplace(container, availability: availability,
                                           recoveryBackupURL: recoveryURL, committed: false)
            } catch {
                Self.logger.error("Backup rollback cleanup remains incomplete; writes are blocked until restart.")
            }
            throw DatabaseBackupError.rollbackCleanupFailed(
                original: original.localizedDescription, cleanup: error.localizedDescription)
        }
        throw original
    }

    private func requireUnchanged(_ archive: DatabaseArchive) throws {
        var current = try DatabaseArchive.capture(ModelContext(container), now: archive.createdAt)
        current.archivedReservationJSON = try maintenance.reservationSnapshot(for: container)
        guard current == archive else { throw DatabaseBackupError.changed }
        guard !container.mainContext.hasChanges else { throw DatabaseBackupError.changed }
    }

    private func requireStorage() throws {
        guard !availability.areWritesUnavailable else { throw DatabaseBackupError.unavailable }
    }
}
