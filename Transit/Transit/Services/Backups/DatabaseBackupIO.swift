import Foundation
import SwiftData

/// Each synchronous call owns its contexts and models on the calling executor.
/// Only immutable archives cross to the serial background writer; installed models never do.
nonisolated enum DatabaseBackupIO {
    static func encoded(_ archive: DatabaseArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= DurableBackupFile.maximumBytes else {
            throw DatabaseBackupError.invalidArchive("Backup exceeds the 128 MB safety limit.")
        }
        return data
    }

    static func verify(_ data: Data) throws -> DatabaseArchive {
        guard data.count <= DurableBackupFile.maximumBytes else {
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
        let inserted = try archive.insert(into: context)
        try context.save()
        let order = inserted.mapValues { $0.map(\.persistentModelID) }
        var restored = try DatabaseArchive.capture(ModelContext(scratch), now: archive.createdAt, ordering: order)
        restored.archivedReservationJSON = archive.archivedReservationJSON
        guard restored == archive else {
            throw DatabaseBackupError.invalidArchive(
                "Backup did not pass the full database restore check.")
        }
        return archive
    }

    /// An invalid archive never replaces the destination or appears as a published backup.
    static func export(
        _ archive: DatabaseArchive, to url: URL,
        verify verifier: (Data) throws -> DatabaseArchive = Self.verify,
        cleanupStaging: (URL) throws -> Void = { try BackupStagingFiles.removeStale(in: $0) }
    ) throws -> DatabaseArchive {
        // Cleanup is auxiliary: even listing failure must not block a new recoverable backup.
        try? cleanupStaging(url.deletingLastPathComponent())
        let data = try encoded(archive)
        let staging = try BackupStagingFiles.create(in: url.deletingLastPathComponent())
        defer {
            try? staging.handle.close()
            try? FileManager.default.removeItem(at: staging.url)
        }
        try staging.handle.write(contentsOf: data)
        try DurableBackupFile.synchronize(staging.url)
        let restored = try verifier(DurableBackupFile.read(staging.url))
        guard restored == archive else { throw DatabaseBackupError.changed }
        try DurableBackupFile.publish(staging.url, to: url)
        return restored
    }
}

/// Actor isolation keeps encoding, disk I/O and the complete scratch restore off the UI actor.
actor DatabaseBackupWriter {
    private let operation: @Sendable (DatabaseArchive, URL) throws -> DatabaseArchive

    init(operation: @escaping @Sendable (DatabaseArchive, URL) throws -> DatabaseArchive = {
        try DatabaseBackupIO.export($0, to: $1)
    }) {
        self.operation = operation
    }

    func export(_ archive: DatabaseArchive, to url: URL) throws -> DatabaseArchive {
        try operation(archive, url)
    }

    func preparedData(for archive: DatabaseArchive) throws -> Data {
        let data = try DatabaseBackupIO.encoded(archive)
        _ = try DatabaseBackupIO.verify(data)
        return data
    }

    func readAndVerify(_ url: URL, synchronize: Bool = false) throws -> DatabaseArchive {
        if synchronize { try DurableBackupFile.synchronize(url) }
        return try DatabaseBackupIO.verify(DurableBackupFile.read(url))
    }

    /// Copy the original recovery bytes, without accessing or recapturing the installed store.
    func verifiedFileData(_ url: URL) throws -> Data {
        let data = try DurableBackupFile.read(url)
        _ = try DatabaseBackupIO.verify(data)
        return data
    }
}
