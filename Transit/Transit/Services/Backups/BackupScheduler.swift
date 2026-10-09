import Foundation
import Observation

/// A running Mac app checks once per minute. Sleep/closure produces one catch-up export, never a launch agent.
@MainActor @Observable
final class BackupScheduler {
    private let service: DatabaseBackupService
    private let defaults: UserDefaults
    private let writer: DatabaseBackupWriter
    private let openDirectory: @MainActor (Data) throws -> BackupDirectoryAccess
    private var isExporting = false
    private var loop: Task<Void, Never>?
    private(set) var lastError: String?
    private(set) var lastSuccess: Date?

    init(service: DatabaseBackupService, defaults: UserDefaults = .standard,
         writer: DatabaseBackupWriter = DatabaseBackupWriter(),
         openDirectory: @escaping @MainActor (Data) throws -> BackupDirectoryAccess = BackupDirectoryAccess.open) {
        self.service = service
        self.defaults = defaults
        self.writer = writer
        self.openDirectory = openDirectory
        lastError = defaults.string(forKey: "backup.lastError")
        lastSuccess = defaults.object(forKey: "backup.lastSuccess") as? Date
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func check(now: Date = .now) async {
        guard !isExporting else { return }
        guard defaults.bool(forKey: "backup.scheduleEnabled"),
            let enabledAt = defaults.object(forKey: "backup.enabledAt") as? Date
        else { return }
        if let retry = defaults.object(forKey: "backup.nextAttempt") as? Date, now < retry { return }
        guard let bookmark = defaults.data(forKey: "backup.directoryBookmark") else {
            recordFailure("Choose a backup folder to enable scheduled exports.", now: now)
            return
        }
        let hour = defaults.object(forKey: "backup.hour") as? Int ?? 2
        let minute = defaults.object(forKey: "backup.minute") as? Int ?? 0
        guard
            BackupSchedule(hour: hour, minute: minute).isDue(
                now: now, lastSuccess: lastSuccess,
                enabledAt: enabledAt)
        else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let access = try openDirectory(bookmark)
            defer { access.close() }
            if let renewed = access.renewedBookmark {
                defaults.set(renewed, forKey: "backup.directoryBookmark")
            }
            let name = "Transit-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString).transitbackup"
            let archive = try service.capture()
            _ = try await writer.export(archive, to: access.url.appendingPathComponent(name))
            lastSuccess = now
            defaults.set(now, forKey: "backup.lastSuccess")
            lastError = nil
            defaults.removeObject(forKey: "backup.lastError")
            defaults.removeObject(forKey: "backup.nextAttempt")
            defaults.set(
                DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .short),
                forKey: "backup.lastSuccessfulExport")
        } catch {
            recordFailure(error.localizedDescription, now: now)
        }
    }

    private func recordFailure(_ message: String, now: Date) {
        lastError = message
        defaults.set(message, forKey: "backup.lastError")
        defaults.set(now.addingTimeInterval(3600), forKey: "backup.nextAttempt")
    }
}
