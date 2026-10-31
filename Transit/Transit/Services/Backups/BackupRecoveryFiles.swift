import Foundation

nonisolated enum BackupRecoveryFiles {
    static func directory(
        applicationSupportDirectory: URL = .applicationSupportDirectory,
        mode: AppPersistencePolicy.Mode = AppPersistencePolicy.current
    ) throws -> URL {
        PersistenceStoreLocation.recoveryDirectory(for: mode, applicationSupportDirectory: applicationSupportDirectory)
    }

    static func newURL() throws -> URL {
        let folder = try directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try BackupFilename.availableURL(in: folder)
    }

    /// Only published recovery files owned by this feature, never arbitrary app-private files.
    static func available(in folder: URL) throws -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch CocoaError.fileReadNoSuchFile { return [] }
        return try entries.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            let legacy = ["BeforeImport-", "BeforeWipe-"].contains { prefix in
                name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
            }
            guard url.pathExtension == "transitbackup",
                  legacy || BackupFilename.isGenerated(url.lastPathComponent) else { return false }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
