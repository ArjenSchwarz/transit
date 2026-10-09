import Foundation

/// Keeps the selected folder's security scope open until the background export finishes.
@MainActor
struct BackupDirectoryAccess {
    let url: URL
    var renewedBookmark: Data?
    var close: () -> Void = {}

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
