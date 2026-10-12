import Darwin
import Foundation

/// ISO 8601 basic notation avoids colons and other nonportable filename characters.
nonisolated enum BackupFilename {
    private static let style = Date.ISO8601FormatStyle(
        dateSeparator: .omitted, timeSeparator: .omitted, timeZoneSeparator: .omitted,
        includingFractionalSeconds: false, timeZone: TimeZone(secondsFromGMT: 0)!)

    static func name(at date: Date = .now) -> String {
        "transit-\(date.formatted(style)).transitbackup"
    }

    static func isGenerated(_ name: String) -> Bool {
        name.range(
            of: #"^transit-[0-9]{8}T[0-9]{6}Z(?:-(?:[2-9]|[1-9][0-9]+))?\.transitbackup$"#,
            options: .regularExpression) != nil
    }

    /// Name selection is advisory. Publication must also refuse replacement atomically.
    static func availableURL(in directory: URL, at date: Date = .now) throws -> URL {
        let base = name(at: date)
        for attempt in 1...1000 {
            let filename = attempt == 1 ? base
                : String(base.dropLast(".transitbackup".count)) + "-\(attempt).transitbackup"
            let url = directory.appendingPathComponent(filename)
            var info = stat()
            if lstat(url.path, &info) == 0 { continue }
            guard errno == ENOENT else {
                throw DatabaseBackupError.invalidArchive("The backup destination could not be checked.")
            }
            return url
        }
        throw DatabaseBackupError.invalidArchive("Too many backups have the same timestamp. Try the export again.")
    }
}
