import CloudKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct TransitBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw DatabaseBackupError.invalidArchive("Select a Transit backup file.")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DatabaseBackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncManager.self) private var syncManager
    @State private var exportedArchive: DatabaseArchive?
    @State private var document: TransitBackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var incoming: DatabaseArchive?
    @State private var wipeBackupURL: URL?
    @State private var preparingWipe = false
    @State private var wipeConfirmation = ""
    @State private var confirmingWipe = false
    @State private var message: String?
    @State private var busy = false
    @State private var recoveryRefresh = UUID()
    @State private var importStage: DatabaseBackupService.ImportStage?
    @State private var folderPicker = false
    #if os(macOS)
    @AppStorage("backup.scheduleEnabled") private var scheduled = false
    @AppStorage("backup.hour") private var hour = 2
    @AppStorage("backup.minute") private var minute = 0
    @AppStorage("backup.lastError") private var scheduleError = ""
    @AppStorage("backup.lastSuccessfulExport") private var lastScheduledExport = "No successful scheduled export yet"
    @AppStorage("backup.folderName") private var folderName = "No folder selected"
    #endif

    private var service: DatabaseBackupService { DatabaseBackupService(container: context.container) }

    var body: some View {
        Form {
            Section("Database Backup") {
                Text(
                    """
                    Exports include every saved project, task, milestone, comment, relationship and
                    history record. Backups contain your private data; keep them somewhere safe.
                    """
                )
                Button("Export Everything…") { export() }.accessibilityIdentifier("backup.export")
                Button("Import Backup…") { importing = true }.accessibilityIdentifier("backup.import")
                Text(
                    """
                    Import replaces the saved database. Transit first creates a recovery backup. With
                    iCloud enabled, replacement syncs to your other devices.
                    """
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            scheduleSection
            #endif
            Section("Wipe Everything") {
                Text(
                    """
                    Deletes all saved Transit data. With iCloud sync active, deletions also sync to
                    iCloud and other devices. Quit Transit on other devices first; offline edits can
                    reappear later. A new recoverable backup must be saved and verified before
                    confirmation.
                    """
                )
                Button("Create Backup Before Wipe…", role: .destructive) {
                    preparingWipe = true
                    export()
                }.accessibilityIdentifier("backup.prepareWipe")
            }
            Section { BackupRecoveryView().id(recoveryRefresh) }
            if busy { Section { ProgressView(importStage?.title ?? "Working with backup…") } }
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .formStyle(.grouped)
        .navigationTitle("Backups")
        .disabled(busy)
        .fileExporter(
            isPresented: $exporting, document: document, contentTypes: [.json],
            defaultFilename: "Transit-\(Int(Date.now.timeIntervalSince1970)).transitbackup",
            onCompletion: handleExport,
            onCancellation: {
                preparingWipe = false
                exportedArchive = nil
                document = nil
                wipeBackupURL = nil
                message = nil
            }
        )
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "Replace the saved database?",
            isPresented: Binding(
                get: { incoming != nil }, set: { if !$0 { incoming = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Create Recovery Backup and Replace", role: .destructive) { performImport() }
            Button("Cancel", role: .cancel) { incoming = nil }
        } message: {
            Text(
                """
                All current records will be replaced by this backup. A verified recovery file
                will be kept in Transit's Backups folder.
                """
            )
        }
        .alert("Permanently wipe all Transit data?", isPresented: $confirmingWipe) {
            TextField("Type WIPE", text: $wipeConfirmation)
            Button("Wipe Everything", role: .destructive) { performWipe() }
            Button("Cancel", role: .cancel) {
                wipeBackupURL = nil
                wipeConfirmation = ""
            }
        } message: {
            Text(
                """
                A verified recovery backup is kept by Transit, and your selected copy was checked.
                File-provider upload completion cannot be guaranteed. This deletes the saved database and, with sync
                active, its iCloud data. Type WIPE to continue.
                """
            )
        }
        #if os(macOS)
        .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in
            runBackupOperation {
                let url = try result.get()
                let bookmark = try await BackupDirectoryAccess.prepareBookmark(for: url)
                UserDefaults.standard.set(bookmark, forKey: "backup.directoryBookmark")
                UserDefaults.standard.removeObject(forKey: "backup.nextAttempt")
                scheduleError = ""
                folderName = url.lastPathComponent
                message = "Backup folder access checked. Scheduled exports will use this folder."
            }
        }
        #endif
    }

    #if os(macOS)
    private var scheduleSection: some View {
        Section("Scheduled Exports (Mac)") {
            Toggle("Export Every Day", isOn: $scheduled)
                .onChange(of: scheduled) { _, enabled in
                    if enabled { UserDefaults.standard.set(Date.now, forKey: "backup.enabledAt") }
                }
                .accessibilityIdentifier("backup.schedule")
            BackupScheduleTimePicker(hour: $hour, minute: $minute)
            Text("Time format follows your Mac’s region settings. You can type the hour and minute.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Choose Backup Folder…") { folderPicker = true }
            Text(folderName).foregroundStyle(.secondary)
            Text("Last scheduled export: " + lastScheduledExport).font(.caption)
            if !scheduleError.isEmpty {
                Text(scheduleError + " Retry in up to one hour, or choose the folder again.")
                    .foregroundStyle(.red).accessibilityIdentifier("backup.scheduleError")
            }
            Text(
                """
                Uses this Mac's local time while Transit is running. If the Mac sleeps or Transit is
                closed, one missed export runs when Transit next runs. Files are kept until you
                remove them. No scheduled exports run on iPhone or iPad.
                """
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
    #endif

}

extension DatabaseBackupView {
    private func runBackupOperation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer {
                busy = false
                importStage = nil
                recoveryRefresh = UUID()
            }
            do { try await operation() } catch {
                preparingWipe = false
                message = error.localizedDescription
            }
        }
    }

    private func export() {
        runBackupOperation {
            guard !context.hasChanges else { throw DatabaseBackupError.changed }
            let prepared = try await service.preparedExport()
            exportedArchive = prepared.archive
            document = TransitBackupDocument(data: prepared.data)
            exporting = true
        }
    }

    private func handleExport(_ result: Result<URL, any Error>) {
        runBackupOperation {
            defer { preparingWipe = false }
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let expected = exportedArchive else { throw DatabaseBackupError.changed }
            if preparingWipe {
                let recovery = try BackupRecoveryFiles.newURL(beforeWipe: true)
                try await service.retainWipeRecovery(selectedURL: url, expected: expected, recoveryURL: recovery)
                wipeBackupURL = recovery
                wipeConfirmation = ""
                confirmingWipe = true
            } else {
                guard try await service.readAndVerify(url) == expected else { throw DatabaseBackupError.changed }
            }
            message = "Backup saved and its complete restore verified: \(url.lastPathComponent)"
        }
    }

    private func handleImport(_ result: Result<URL, any Error>) {
        runBackupOperation {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            incoming = try await service.readAndVerify(url)
        }
    }

    private func recoveryURL() throws -> URL {
        try BackupRecoveryFiles.newURL()
    }

    private func performImport() {
        guard let archive = incoming else { return }
        incoming = nil
        runBackupOperation {
            let recovery = try recoveryURL()
            try await service.replace(with: archive, recoveryURL: recovery) { importStage = $0 }
            message =
                """
                Database imported. Save recovery copies from the completion screen, then quit
                and reopen Transit before editing restored records.
                """
        }
    }

    private func performWipe() {
        guard let url = wipeBackupURL else { return }
        let confirmation = wipeConfirmation
        runBackupOperation {
            defer {
                wipeBackupURL = nil
                wipeConfirmation = ""
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard confirmation == "WIPE" else { throw DatabaseBackupError.confirmationRequired }
            let archive = try await service.readAndVerify(url)
            if syncManager.cloudSyncAllowed && !syncManager.isCloudSyncActive {
                throw DatabaseBackupError.invalidArchive(
                    "Enable iCloud sync and restart Transit before wiping iCloud data.")
            }
            if syncManager.isCloudSyncActive {
                guard let identifier = context.container.configurations.first?.cloudKitContainerIdentifier
                else {
                    throw DatabaseBackupError.unavailable
                }
                try await CloudBackupCoverage(
                    database: CKContainer(identifier: identifier).privateCloudDatabase
                ).verify(archive)
            }
            try await service.wipe(backupURL: url, confirmation: confirmation, expectedArchive: archive)
            message =
                syncManager.isCloudSyncActive
                ? """
                All saved data deleted. iCloud deletions will propagate as sync completes. Quit
                and reopen Transit. Keep your backup.
                """
                : "All saved data deleted. Quit and reopen Transit. Keep your backup."
        }
    }
}
