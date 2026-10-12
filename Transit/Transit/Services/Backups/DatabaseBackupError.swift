import Foundation

nonisolated enum DatabaseBackupError: LocalizedError {
    case invalidArchive(String)
    case unavailable
    case changed
    case confirmationRequired
    case rollbackCleanupFailed(original: String, cleanup: String)
    case cleanupAfterCommit

    var errorDescription: String? {
        switch self {
        case .invalidArchive(let message): message
        case .unavailable: "The persistent database is unavailable. Restart Transit before continuing."
        case .changed:
            "The database changed after the backup was created. Create a new backup before continuing."
        case .confirmationRequired: "Type WIPE to confirm permanent deletion."
        case .rollbackCleanupFailed(let original, let cleanup):
            """
            Database change failed: \(original). Retry cleanup also failed: \(cleanup).
            Quit Transit and keep the recovery backup before reopening.
            """
        case .cleanupAfterCommit:
            """
            Database replacement was saved, but retry cleanup failed. Quit Transit and keep
            the verified recovery backup before reopening.
            """
        }
    }
}
