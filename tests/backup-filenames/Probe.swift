import Foundation

/// Standalone filename checks: no app, model container, defaults or cloud access.
@main struct BackupFilenameProbe {
    struct Failure: Error { let message: String }

    static func main() throws {
        var passed: [String] = []
        let date = Date(timeIntervalSince1970: 1_791_684_000)
        let name = "transit-20261011T020000Z.transitbackup"
        try checkFormat(date: date, name: name)
        passed.append("UTC ISO timestamp and exact archive extension")

        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try BackupFilename.availableURL(in: folder, at: date)
        let original = Data("existing backup".utf8)
        try original.write(to: first)
        let second = try BackupFilename.availableURL(in: folder, at: date)
        try expect(second.lastPathComponent == "transit-20261011T020000Z-2.transitbackup", "Readable collision suffix")
        try FileManager.default.createSymbolicLink(
            at: second, withDestinationURL: folder.appendingPathComponent("missing"))
        let third = try BackupFilename.availableURL(in: folder, at: date)
        try expect(third.lastPathComponent == "transit-20261011T020000Z-3.transitbackup",
                   "Broken symlink counts as occupied")
        try expect(BackupFilename.isGenerated(third.lastPathComponent), "Collision name recognized")
        try expect(try Data(contentsOf: first) == original, "Name selection preserves existing backup")
        passed.append("Numbered collisions and occupied symlinks")

        let staging = folder.appendingPathComponent("scratch")
        let replacement = Data("new backup".utf8)
        try replacement.write(to: staging)
        // Simulate a competing writer arriving after availableURL returned.
        try original.write(to: third)
        do {
            try DurableBackupFile.publish(staging, to: third)
            throw Failure(message: "Publication replaced a competing backup")
        } catch is DatabaseBackupError {
            try expect(try Data(contentsOf: third) == original, "Atomic collision preserves destination")
            try expect(try Data(contentsOf: staging) == replacement, "Failed publication preserves staging")
        }
        try FileManager.default.removeItem(at: third)
        try DurableBackupFile.publish(staging, to: third)
        try expect(try Data(contentsOf: third) == replacement, "Unoccupied generated destination publishes")
        passed.append("Atomic no-overwrite publication after selection race")

        try checkDiscovery(in: folder, first: first, third: third, original: original)
        passed.append("Legacy and new recovery discovery without migration")

        try writeJUnit(passed)
        print("\(passed.count) filename checks passed. Example: \(name)")
    }

    private static func checkDiscovery(in folder: URL, first: URL, third: URL, original: Data) throws {
        let legacy = folder.appendingPathComponent("BeforeImport-\(UUID()).transitbackup")
        try original.write(to: legacy)
        let legacyWipe = folder.appendingPathComponent("BeforeWipe-\(UUID()).transitbackup")
        try original.write(to: legacyWipe)
        let unknown = folder.appendingPathComponent("unrelated.transitbackup")
        try original.write(to: unknown)
        let directoryName = folder.appendingPathComponent("transit-20261011T020001Z.transitbackup")
        try FileManager.default.createDirectory(at: directoryName, withIntermediateDirectories: false)
        let listed = Set(try BackupRecoveryFiles.available(in: folder))
        let expectedNames = Set([first, third, legacy, legacyWipe].map(\.lastPathComponent))
        try expect(Set(listed.map(\.lastPathComponent)) == expectedNames,
                   "Legacy/new files only; symlinks/directories excluded")
        try expect(try Data(contentsOf: legacy) == original, "Legacy backups not renamed or modified")
    }

    private static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.resolvingSymlinksInPath()
    }

    private static func writeJUnit(_ passed: [String]) throws {
        if CommandLine.arguments.count > 1 {
            let rows = passed.map { "<testcase classname=\"BackupFilenameProbe\" name=\"\($0)\"/>" }.joined()
            let xml = "<testsuite name=\"Backup filenames\" tests=\"\(passed.count)\" failures=\"0\" errors=\"0\">"
                + rows + "</testsuite>"
            try xml.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    private static func checkFormat(date: Date, name: String) throws {
        try expect(BackupFilename.name(at: date) == name, "Exact UTC ISO name")
        try expect(BackupFilename.name(at: date.addingTimeInterval(0.9)) == name, "Whole-second resolution")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        let offsetDate = try unwrap(parser.date(from: "2026-10-11T13:00:00+11:00"))
        try expect(BackupFilename.name(at: offsetDate) == name, "Offset input must normalize to UTC")
        try expect(BackupFilename.isGenerated(name), "Generated name recognized")
        try expect(!name.contains(":"), "Filename must avoid colons")
        try expect(!BackupFilename.isGenerated("transit-random.transitbackup"), "Unknown names excluded")
    }

    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure(message: "Unable to parse fixture date") }
        return value
    }
}
