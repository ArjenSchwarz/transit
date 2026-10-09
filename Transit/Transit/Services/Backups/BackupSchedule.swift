#if os(macOS)
import Foundation
import Observation

nonisolated struct BackupSchedule: Equatable {
    var hour: Int
    var minute: Int

    func latestDue(before now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now.addingTimeInterval(1), matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .backward)
    }

    func isDue(now: Date, lastSuccess: Date?, enabledAt: Date, calendar: Calendar = .current)
        -> Bool {
        guard let due = latestDue(before: now, calendar: calendar), due >= enabledAt else {
            return false
        }
        return lastSuccess.map { $0 < due } ?? true
    }
}

/// A running Mac app checks once per minute. Sleep/closure produces one catch-up export, never a launch agent.
@MainActor @Observable
final class BackupScheduler {
    private let service: DatabaseBackupService
    private let defaults: UserDefaults
    private var loop: Task<Void, Never>?
    private(set) var lastError: String?
    private(set) var lastSuccess: Date?

    init(service: DatabaseBackupService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        lastSuccess = defaults.object(forKey: "backup.lastSuccess") as? Date
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func check(now: Date = .now) {
        guard defaults.bool(forKey: "backup.scheduleEnabled"),
            let enabledAt = defaults.object(forKey: "backup.enabledAt") as? Date,
            let bookmark = defaults.data(forKey: "backup.directoryBookmark")
        else { return }
        let hour = defaults.object(forKey: "backup.hour") as? Int ?? 2
        let minute = defaults.object(forKey: "backup.minute") as? Int ?? 0
        guard
            BackupSchedule(hour: hour, minute: minute).isDue(
                now: now, lastSuccess: lastSuccess,
                enabledAt: enabledAt)
        else { return }
        do {
            var stale = false
            let directory = try URL(
                resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, directory.startAccessingSecurityScopedResource() else {
                throw DatabaseBackupError.invalidArchive(
                    "Choose the backup folder again to renew access.")
            }
            defer { directory.stopAccessingSecurityScopedResource() }
            let name = "Transit-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString).transitbackup"
            _ = try service.export(to: directory.appendingPathComponent(name))
            lastSuccess = now
            defaults.set(now, forKey: "backup.lastSuccess")
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }
}
#endif
