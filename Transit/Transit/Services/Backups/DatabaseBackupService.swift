import Foundation
import Observation
import SwiftData

/// All mutation uses an owned context. Validation never touches the installed store.
@MainActor @Observable
final class DatabaseBackupService {
    let container: ModelContainer
    private let maintenance: DatabaseMaintenanceGate
    private let availability: PersistenceAvailability
    private let save: (ModelContext) throws -> Void

    init(
        container: ModelContainer, availability: PersistenceAvailability = .shared,
        maintenance: DatabaseMaintenanceGate = .shared,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.availability = availability
        self.maintenance = maintenance
        self.save = save
    }

    func capture() throws -> DatabaseArchive {
        try requireStorage()
        var archive = try DatabaseArchive.capture(ModelContext(container))
        archive.archivedReservationJSON = try maintenance.reservationSnapshot(for: container)
        return archive
    }

    func encoded(_ archive: DatabaseArchive) throws -> Data {
        try DatabaseBackupIO.encoded(archive)
    }

    func decodeAndVerify(_ data: Data) throws -> DatabaseArchive {
        try DatabaseBackupIO.verify(data)
    }

    func export(to url: URL) throws -> DatabaseArchive {
        try DatabaseBackupIO.export(capture(), to: url)
    }

    /// Replace semantics are deliberate: no deduplication, ID allocation or raw-value normalization.
    /// A fresh recovery archive must already exist outside the database at the selected destination.
    func replace(with archive: DatabaseArchive, recoveryURL: URL) throws {
        try requireStorage()
        _ = try decodeAndVerify(encoded(archive))
        let before = try export(to: recoveryURL)
        try requireUnchanged(before)
        try maintenance.authorizeReplacement(of: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try DatabaseArchive.deleteAll(in: context)
            _ = try archive.insert(into: context)
            try save(context)
        } catch {
            try rollback(context, original: error)
        }
        do { try maintenance.didReplace(container, availability: availability) } catch {
            throw DatabaseBackupError.cleanupAfterCommit
        }
    }

    /// The exact archive read back from disk authorizes only its unchanged saved dataset.
    func wipe(backupURL: URL, confirmation: String) throws {
        guard confirmation == "WIPE" else { throw DatabaseBackupError.confirmationRequired }
        try requireStorage()
        let archive = try decodeAndVerify(DurableBackupFile.read(backupURL))
        try requireUnchanged(archive)
        try maintenance.authorizeReplacement(of: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try DatabaseArchive.deleteAll(in: context)
            try save(context)
        } catch {
            try rollback(context, original: error)
        }
        do { try maintenance.didReplace(container, availability: availability) } catch {
            throw DatabaseBackupError.cleanupAfterCommit
        }
    }

    private func rollback(_ context: ModelContext, original: any Error) throws -> Never {
        context.rollback()
        do {
            try maintenance.cancelReplacement(of: container)
        } catch {
            // A retry journal with uncertain cleanup must not accept more edits before restart.
            try? maintenance.didReplace(container, availability: availability)
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
