import Darwin
import Foundation

nonisolated enum DurableBackupFile {
    static let maximumBytes = 128 * 1024 * 1024

    static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while let chunk = try handle.read(upToCount: min(1024 * 1024, maximumBytes + 1 - result.count)),
              !chunk.isEmpty {
            result.append(chunk)
            guard result.count <= maximumBytes else {
                throw DatabaseBackupError.invalidArchive("Backup exceeds the 128 MB safety limit.")
            }
        }
        return result
    }

    static func synchronize(_ url: URL) throws {
        let descriptor = open(url.path, O_RDWR)
        guard descriptor >= 0 else {
            throw DatabaseBackupError.invalidArchive("Backup could not be opened for verification.")
        }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else {
            throw DatabaseBackupError.invalidArchive(
                "The backup destination could not confirm a durable save. Choose a local folder.")
        }
        try synchronizeDirectory(for: url)
    }

    /// Same-directory rename atomically replaces the destination only after verification.
    static func publish(_ staging: URL, to destination: URL) throws {
        guard rename(staging.path, destination.path) == 0 else {
            throw DatabaseBackupError.invalidArchive("The verified backup could not be saved at this destination.")
        }
        try synchronizeDirectory(for: destination)
    }

    private static func synchronizeDirectory(for url: URL) throws {
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else {
            throw DatabaseBackupError.invalidArchive("The backup folder could not be opened for durable save.")
        }
        defer { close(directory) }
        guard fsync(directory) == 0 else {
            throw DatabaseBackupError.invalidArchive("The backup folder could not confirm a durable save.")
        }
    }
}
