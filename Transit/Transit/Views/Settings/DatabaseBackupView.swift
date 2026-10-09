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
            if let message { Section { Text(message).textSelection(.enabled) } }
        }
        .formStyle(.grouped)
        .navigationTitle("Backups")
        .disabled(busy)
        .fileExporter(
            isPresented: $exporting, document: document, contentType: .json,
            defaultFilename: "Transit-\(Int(Date.now.timeIntervalSince1970)).transitbackup"
        ) { result in
            handleExport(result)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                incoming = try service.decodeAndVerify(DurableBackupFile.read(url))
            } catch { message = error.localizedDescription }
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
                Your verified backup is saved. This deletes the saved database and, with sync
                active, its iCloud data. Type WIPE to continue.
                """
            )
        }
        #if os(macOS)
        .fileImporter(isPresented: $folderPicker, allowedContentTypes: [.folder]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                    relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: "backup.directoryBookmark")
                UserDefaults.standard.removeObject(forKey: "backup.nextAttempt")
                scheduleError = ""
                folderName = url.lastPathComponent
            } catch { message = error.localizedDescription }
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
            HStack {
                Picker("Hour", selection: $hour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                Picker("Minute", selection: $minute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
            }
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
    private func export() {
        do {
            guard !context.hasChanges else { throw DatabaseBackupError.changed }
            let archive = try service.capture()
            let data = try service.encoded(archive)
            _ = try service.decodeAndVerify(data)
            exportedArchive = archive
            document = TransitBackupDocument(data: data)
            exporting = true
        } catch {
            preparingWipe = false
            message = error.localizedDescription
        }
    }

    private func handleExport(_ result: Result<URL, any Error>) {
        defer { preparingWipe = false }
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            try DurableBackupFile.synchronize(url)
            let verified = try service.decodeAndVerify(DurableBackupFile.read(url))
            guard verified == exportedArchive else {
                throw DatabaseBackupError.changed
            }
            message = "Backup saved and its complete restore verified: \(url.lastPathComponent)"
            if preparingWipe {
                wipeBackupURL = url
                wipeConfirmation = ""
                confirmingWipe = true
            }
        } catch { message = error.localizedDescription }
    }

    private func recoveryURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("BeforeImport-\(UUID().uuidString).transitbackup")
    }

    private func performImport() {
        guard let archive = incoming else { return }
        incoming = nil
        do {
            let recovery = try recoveryURL()
            try service.replace(with: archive, recoveryURL: recovery)
            message =
                """
                Database imported. Recovery backup: \(recovery.path). Quit and reopen Transit
                before editing restored records.
                """
        } catch { message = error.localizedDescription }
    }

    private func performWipe() {
        guard let url = wipeBackupURL else { return }
        busy = true
        Task { @MainActor in
            defer {
                busy = false
                wipeBackupURL = nil
                wipeConfirmation = ""
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard wipeConfirmation == "WIPE" else { throw DatabaseBackupError.confirmationRequired }
                let archive = try service.decodeAndVerify(DurableBackupFile.read(url))
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
                try service.wipe(backupURL: url, confirmation: wipeConfirmation)
                message =
                    syncManager.isCloudSyncActive
                    ? """
                    All saved data deleted. iCloud deletions will propagate as sync completes. Quit
                    and reopen Transit. Keep your backup.
                    """
                    : "All saved data deleted. Quit and reopen Transit. Keep your backup."
            } catch { message = error.localizedDescription }
        }
    }
}
