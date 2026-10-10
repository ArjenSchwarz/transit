import SwiftUI
import UniformTypeIdentifiers

/// No model queries or mutation actions: usable outside the editing lock after replacement.
struct BackupCompletionView: View {
    let gate: DatabaseMaintenanceGate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(gate.replacementCommitted ? "Database change complete" : "Recovery needs a restart")
                    .font(.title2).accessibilityIdentifier("backup.completionTitle")
                Text(gate.replacementCommitted
                     ? "Your database change was saved. Editing is paused to protect your data."
                     : "The change failed and cleanup is uncertain. Editing is paused to protect your data.")
                Text("Quit and reopen this copy of Transit before editing. You can save recovery copies below first.")
                    .accessibilityIdentifier("backup.restartGuidance")
                BackupRecoveryView(featuredURL: gate.recoveryBackupURL)
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityIdentifier("backup.completion")
    }
}

struct BackupRecoveryView: View {
    var featuredURL: URL?
    @State private var files: [URL] = []
    @State private var message: String?
    @State private var copying = false
    @State private var presenting = false
    @State private var document: TransitBackupDocument?
    @State private var filename = "Recovery.transitbackup"
    private let writer = DatabaseBackupWriter()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery Backups").font(.headline)
            Text(
                "These copies are kept privately by Transit. Save a copy to Files or another folder "
                + "to keep it outside the app.")
                .font(.caption)
            if files.isEmpty { Text("No automatic recovery backups yet.").font(.caption) }
            ForEach(files, id: \.self) { url in
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent).font(.caption).textSelection(.enabled)
                    Button("Save Recovery Copy…") { saveCopy(url) }
                        .accessibilityIdentifier("backup.saveRecovery")
                        .disabled(copying || presenting)
                }
            }
            if copying { ProgressView("Checking recovery copy…") }
            if let message { Text(message).textSelection(.enabled).accessibilityIdentifier("backup.recoveryMessage") }
        }
        .task { loadFiles() }
        .fileExporter(isPresented: $presenting, document: document, contentTypes: [.json],
                      defaultFilename: filename, onCompletion: { result in
            switch result {
            case .failure(let error):
                let failure = error as NSError
                message = failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError
                    ? nil : error.localizedDescription
            case .success(let url):
                copying = true
                Task {
                    defer {
                        copying = false
                        document = nil
                    }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try await writer.verifiedFileData(url)
                        guard data == document?.data else { throw DatabaseBackupError.changed }
                        message = "Recovery copy saved and checked. The original is still kept by Transit."
                    } catch { message = error.localizedDescription }
                }
            }
        }, onCancellation: {
            presenting = false
            document = nil
            message = nil
        })
    }

    private func loadFiles() {
        files = featuredURL.map { [$0] } ?? []
        do {
            let available = try BackupRecoveryFiles.available(in: BackupRecoveryFiles.directory())
            files += available.filter { !files.contains($0) }
        } catch { message = error.localizedDescription }
    }

    private func saveCopy(_ url: URL) {
        guard !copying && !presenting else { return }
        copying = true
        message = nil
        Task {
            defer { copying = false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                document = TransitBackupDocument(data: try await writer.verifiedFileData(url))
                filename = url.lastPathComponent
                presenting = true
            } catch { message = error.localizedDescription }
        }
    }
}
