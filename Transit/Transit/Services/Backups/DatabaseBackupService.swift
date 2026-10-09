import Foundation
import Observation
import SwiftData

nonisolated enum DatabaseBackupError: LocalizedError {
    case invalidArchive(String)
    case unavailable
    case changed
    case confirmationRequired
    case cleanupAfterCommit

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let message): message
        case .unavailable: "The persistent database is unavailable. Restart Transit before continuing."
        case .changed:
            "The database changed after the backup was created. Create a new backup before continuing."
        case .confirmationRequired: "Type WIPE to confirm permanent deletion."
        case .cleanupAfterCommit:
            """
            Database replacement was saved, but retry cleanup failed. Quit Transit and keep
            the verified recovery backup before reopening.
            """
        }
    }
}

/// All mutation uses an owned context. Validation never touches the installed store.
@MainActor @Observable
final class DatabaseBackupService {
    let container: ModelContainer
    private let availability: PersistenceAvailability
    private let save: (ModelContext) throws -> Void

    init(
        container: ModelContainer, availability: PersistenceAvailability = .shared,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.availability = availability
        self.save = save
    }

    func capture() throws -> DatabaseArchive {
        try requireStorage()
        var archive = try DatabaseArchive.capture(ModelContext(container))
        archive.archivedReservationJSON = try DatabaseMaintenanceGate.shared.reservationSnapshot(for: container)
        return archive
    }

    func encoded(_ archive: DatabaseArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(archive)
    }

    func decodeAndVerify(_ data: Data) throws -> DatabaseArchive {
        guard data.count <= 128 * 1024 * 1024 else {
            throw DatabaseBackupError.invalidArchive("Backup exceeds the 128 MB safety limit.")
        }
        let archive = try JSONDecoder().decode(DatabaseArchive.self, from: data)
        try archive.validate()
        let schema = DatabaseArchive.schema
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let scratch = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(scratch)
        context.autosaveEnabled = false
        try archive.insert(into: context)
        try context.save()
        var restored = try DatabaseArchive.capture(ModelContext(scratch), now: archive.createdAt)
        restored.archivedReservationJSON = archive.archivedReservationJSON
        guard restored == archive else {
            throw DatabaseBackupError.invalidArchive(
                "Backup did not pass the full database restore check.")
        }
        return archive
    }

    /// Writes atomically, reads the actual destination back, then restores it into an isolated store.
    func export(to url: URL) throws -> DatabaseArchive {
        let archive = try capture()
        try encoded(archive).write(to: url, options: [.atomic])
        let verified = try decodeAndVerify(Data(contentsOf: url))
        guard verified == archive else { throw DatabaseBackupError.changed }
        return verified
    }

    /// Replace semantics are deliberate: no deduplication, ID allocation or raw-value normalization.
    /// A fresh recovery archive must already exist outside the database at the selected destination.
    func replace(with archive: DatabaseArchive, recoveryURL: URL) throws {
        try requireStorage()
        _ = try decodeAndVerify(encoded(archive))
        let before = try export(to: recoveryURL)
        try requireUnchanged(before)
        try DatabaseMaintenanceGate.shared.authorizeReplacement(of: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try DatabaseArchive.deleteAll(in: context)
            try archive.insert(into: context)
            try save(context)

        } catch {
            context.rollback()
            throw error
        }
        do { try DatabaseMaintenanceGate.shared.didReplace(container, availability: availability) } catch {
            throw DatabaseBackupError.cleanupAfterCommit
        }
    }

    /// The exact archive read back from disk authorizes only its unchanged saved dataset.
    func wipe(backupURL: URL, confirmation: String) throws {
        guard confirmation == "WIPE" else { throw DatabaseBackupError.confirmationRequired }
        try requireStorage()
        let archive = try decodeAndVerify(Data(contentsOf: backupURL))
        try requireUnchanged(archive)
        try DatabaseMaintenanceGate.shared.authorizeReplacement(of: container)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try DatabaseArchive.deleteAll(in: context)
            try save(context)

        } catch {
            context.rollback()
            throw error
        }
        do { try DatabaseMaintenanceGate.shared.didReplace(container, availability: availability) } catch {
            throw DatabaseBackupError.cleanupAfterCommit
        }
    }

    private func requireUnchanged(_ archive: DatabaseArchive) throws {
        var current = try DatabaseArchive.capture(ModelContext(container), now: archive.createdAt)
        current.archivedReservationJSON = try DatabaseMaintenanceGate.shared.reservationSnapshot(for: container)
        guard current == archive else { throw DatabaseBackupError.changed }
        guard !container.mainContext.hasChanges else { throw DatabaseBackupError.changed }
    }

    private func requireStorage() throws {
        guard !availability.areWritesUnavailable else { throw DatabaseBackupError.unavailable }
    }
}
