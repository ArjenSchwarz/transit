import Foundation

nonisolated enum BackupRecoveryFiles {
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("Backups")
    }

    static func newURL(beforeWipe: Bool = false) throws -> URL {
        let folder = try directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefix = beforeWipe ? "BeforeWipe-" : "BeforeImport-"
        return folder.appendingPathComponent("\(prefix)\(UUID().uuidString).transitbackup")
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
            guard url.pathExtension == "transitbackup",
                  let prefix = ["BeforeImport-", "BeforeWipe-"].first(where: name.hasPrefix),
                  UUID(uuidString: String(name.dropFirst(prefix.count))) != nil else { return false }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
