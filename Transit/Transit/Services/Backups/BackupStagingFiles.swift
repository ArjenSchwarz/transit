import Darwin
import Foundation

/// Only old, unlocked regular files with our exact staging name are disposable.
/// Published backups, symlinks, unknown files and in-progress writers are never swept.
nonisolated enum BackupStagingFiles {
    static let staleAfter: TimeInterval = 24 * 60 * 60

    static func create(in directory: URL) throws -> (url: URL, handle: FileHandle) {
        let url = directory.appendingPathComponent(".Transit-" + UUID().uuidString + ".pending")
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let reason = String(cString: strerror(errno))
            throw DatabaseBackupError.invalidArchive("The backup staging file could not be created: \(reason).")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let reason = String(cString: strerror(errno))
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw DatabaseBackupError.invalidArchive("The backup staging file could not be locked: \(reason).")
        }
        return (url, handle)
    }

    static func removeStale(in directory: URL, now: Date = .now) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        for url in files where isStagingName(url.lastPathComponent) {
            let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            let modified = TimeInterval(info.st_mtimespec.tv_sec)
                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
            guard modified <= now.timeIntervalSince1970 - staleAfter else { continue }
            var pathInfo = stat()
            guard lstat(url.path, &pathInfo) == 0,
                  pathInfo.st_ino == info.st_ino, pathInfo.st_dev == info.st_dev,
                  pathInfo.st_mode & S_IFMT == S_IFREG else { continue }
            // An undeletable crash remnant must not prevent the next recoverable backup.
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func isStagingName(_ name: String) -> Bool {
        guard name.hasPrefix(".Transit-"), name.hasSuffix(".pending"),
              let id = UUID(uuidString: String(name.dropFirst(9).dropLast(8))) else { return false }
        return name == ".Transit-" + id.uuidString + ".pending"
    }
}
