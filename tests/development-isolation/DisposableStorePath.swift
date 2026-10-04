import Foundation

/// Canonicalize existing directories symmetrically; a new leaf may resolve differently on macOS.
nonisolated enum DisposableStorePath {
    enum Failure: Error, Equatable { case invalidName, missingDirectory, outsideRoot, symbolicLink }

    static func resolve(path: String, rootPath: String) throws -> URL {
        let requested = URL(fileURLWithPath: path).standardizedFileURL
        guard requested.lastPathComponent == "synthetic.store" else { throw Failure.invalidName }
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        let parent = requested.deletingLastPathComponent()
        let files = FileManager.default
        var rootIsDirectory = ObjCBool(false)
        var parentIsDirectory = ObjCBool(false)
        guard files.fileExists(atPath: root.path, isDirectory: &rootIsDirectory), rootIsDirectory.boolValue,
              files.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw Failure.missingDirectory
        }
        let canonicalRoot = root.resolvingSymlinksInPath()
        let canonicalParent = parent.resolvingSymlinksInPath()
        guard canonicalParent.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw Failure.outsideRoot
        }
        let candidate = canonicalParent.appendingPathComponent("synthetic.store")
        // Reject existing and dangling leaf symlinks before a store can be created or opened.
        guard (try? files.destinationOfSymbolicLink(atPath: candidate.path)) == nil else {
            throw Failure.symbolicLink
        }
        return candidate
    }
}
