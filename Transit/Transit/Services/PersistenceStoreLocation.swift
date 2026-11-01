import Foundation

/// Stable new-account locations; selecting them never inspects or copies a legacy store.
nonisolated enum PersistenceStoreLocation {
    static func directory(for mode: AppPersistencePolicy.Mode, applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent(mode.bundleID, isDirectory: true)
    }

    static func storeURL(for mode: AppPersistencePolicy.Mode, applicationSupportDirectory: URL) -> URL? {
        guard !mode.usesMemoryStore else { return nil }
        return directory(for: mode, applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent(mode == .production ? "release.store" : "development.store")
    }

    static func recoveryDirectory(for mode: AppPersistencePolicy.Mode, applicationSupportDirectory: URL) -> URL {
        directory(for: mode, applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("Backups", isDirectory: true)
    }
}
