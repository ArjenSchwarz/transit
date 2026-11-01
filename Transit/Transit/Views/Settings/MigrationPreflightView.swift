import SwiftUI

/// Only this screen is reachable while Release's shared persistence-write gate is closed.
struct MigrationPreflightView: View {
    let preflight: MigrationCounterPreflight
    let onReady: () -> Void
    let enableSync: () -> Void
    @State private var taskFloor = ""
    @State private var milestoneFloor = ""
    @State private var confirmation = ""
    @State private var report = ""
    @State private var presentation = MigrationLaunchPresentation.checking
    @State private var busy = false
    @State private var confirmingPreparation = false

    var body: some View {
        Group {
            if presentation.showsSetup {
                setupForm
            } else {
                ProgressView()
                    .accessibilityLabel("Opening Transit")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 340, idealWidth: 640, minHeight: 500)
        .task { run { await verifySaved() } }
    }

    private var setupForm: some View {
        Form {
            Text("Prepare Transit’s new iCloud destination").font(.headline)
            Text("\(preflight.destination.container) · \(preflight.destination.environment)")
                .textSelection(.enabled)
            Text("Editing and automation stay blocked until both display-ID counters are verified. "
                 + "Inspection reads the Transit data zone; it does not import your backup.")
            Text(report).textSelection(.enabled)
            Button("Retry saved readiness") { run { await verifySaved() } }
            Button("Enable iCloud sync for next launch") {
                enableSync()
                report = "iCloud sync is enabled for the next launch. Quit and reopen Transit to retry readiness."
            }
            Button("Inspect destination") { run { try await inspect() } }
            TextField("Task next-ID floor (at least 2507)", text: $taskFloor)
            TextField("Milestone next-ID floor (at least 22)", text: $milestoneFloor)
            TextField("Confirm the container identifier above", text: $confirmation)
            Text("Use higher verified historical high-water marks when available. "
                 + "Minimums do not certify old-cloud counters.")
                .font(.caption)
            Button("Prepare fresh destination…") { confirmingPreparation = true }
            Button("Verify existing counters without cloud writes") { prepare(fresh: false) }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .confirmationDialog("Advance only the two counters in this fresh destination?",
                            isPresented: $confirmingPreparation) {
            Button("Prepare counters") { prepare(fresh: true) }
        } message: {
            Text("A missing Transit zone will be created. Counters only increase to the entered floors. "
                 + "Existing user records or unknown zones block preparation. No backup is restored.")
        }
    }

    private func verifySaved() async {
        presentation = .checking
        presentation = await MigrationLaunchPresentation.verify(preflight)
        report = presentation.message
        if presentation == .ready { onReady() }
    }

    private func inspect() async throws {
        let inventory = try await preflight.inspect()
        let counts = inventory.counts.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        report = "Transit-zone records: \(counts.isEmpty ? "none" : counts). "
            + "Next IDs: tasks \(inventory.taskCounter), milestones \(inventory.milestoneCounter). "
            + "Fresh graph: \(inventory.isFresh ? "yes" : "no"). "
            + "Unexpected zones/types: \(inventory.unexpectedZones.count)/\(inventory.unexpectedTypes.count). "
            + "Default-zone data is outside this check. Other clients must stay stopped during cutover."
    }

    private func prepare(fresh: Bool) {
        run {
            guard let tasks = Int(taskFloor), let milestones = Int(milestoneFloor) else {
                throw MigrationCounterPreflight.Failure.invalidFloors
            }
            try await preflight.prepare(floors: .init(tasks: tasks, milestones: milestones),
                                        confirmedContainer: confirmation, fresh: fresh)
            onReady()
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() } catch { report = error.localizedDescription }
        }
    }
}
