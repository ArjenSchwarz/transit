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

    /// Replace semantics are deliberate: no deduplication, ID allocation or raw-value normalization.
    /// A fresh recovery archive must already exist outside the database at the selected destination.
    func replace(with archive: DatabaseArchive, recoveryURL: URL) async throws {
        try requireStorage()
        _ = try await writer.preparedData(for: archive)
        let before = try capture()
        _ = try await writer.export(before, to: recoveryURL)
        try commitReplacement(before: before, incoming: archive)
    }

    /// The exact archive read back from disk authorizes only its unchanged saved dataset.
    func wipe(backupURL: URL, confirmation: String, expectedArchive: DatabaseArchive? = nil) async throws {
        guard confirmation == "WIPE" else { throw DatabaseBackupError.confirmationRequired }
        try requireStorage()
        let archive = try await writer.readAndVerify(backupURL)
        if let expectedArchive, expectedArchive != archive { throw DatabaseBackupError.changed }
        try commitReplacement(before: archive, incoming: nil)
    }

    /// Re-check every gate after worker suspension; no await occurs during the final mutation.
    private func commitReplacement(before: DatabaseArchive, incoming: DatabaseArchive?) throws {
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
            try rollback(context, original: error)
        }
        do { try maintenance.didReplace(container, availability: availability) } catch {
            throw DatabaseBackupError.cleanupAfterCommit
        }
    }

    private func rollback(_ context: ModelContext, original: any Error) throws -> Never {
        // This owned failed context is discarded; no registered model escapes to a cached editor.
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
