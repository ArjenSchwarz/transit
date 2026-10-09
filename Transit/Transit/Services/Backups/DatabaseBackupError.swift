import Foundation

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
