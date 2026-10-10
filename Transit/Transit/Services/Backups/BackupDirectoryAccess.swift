import Foundation

/// Keeps the selected folder's security scope open until the background export finishes.
@MainActor
struct BackupDirectoryAccess {
    let url: URL
    var renewedBookmark: Data?
    var close: () -> Void = {}

    #if os(macOS)
    /// Reject unwritable destinations before replacing the user's saved folder.
    static func prepareBookmark(for url: URL) async throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw DatabaseBackupError.invalidArchive("Choose the backup folder again to grant read/write access.")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        try await Task.detached(priority: .userInitiated) { try verifyWritable(url) }.value
        return bookmark
    }

    /// Uses the same creation/flush boundary as scheduled export; never touches existing files.
    nonisolated static func verifyWritable(_ directory: URL) throws {
        let staging = try BackupStagingFiles.create(in: directory)
        defer {
            try? staging.handle.close()
            try? FileManager.default.removeItem(at: staging.url)
        }
        try staging.handle.write(contentsOf: Data([0]))
        try DurableBackupFile.synchronize(staging.url)
        try staging.handle.close()
        try FileManager.default.removeItem(at: staging.url)
    }
    #endif

    static func open(_ bookmark: Data) throws -> Self {
        #if os(macOS)
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else {
            throw DatabaseBackupError.invalidArchive("Choose the backup folder again to renew access.")
        }
        do {
            let renewed = stale ? try url.bookmarkData(options: [.withSecurityScope],
                                                       includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            return Self(url: url, renewedBookmark: renewed, close: { url.stopAccessingSecurityScopedResource() })
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
        #else
        throw DatabaseBackupError.invalidArchive("Scheduled exports are available on Mac only.")
        #endif
    }
}
