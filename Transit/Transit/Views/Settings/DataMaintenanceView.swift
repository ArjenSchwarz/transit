import SwiftUI

/// Settings screen for the duplicate display ID maintenance tool.
/// State machine: `.idle` → `.scanning` → `.scanned(report)` → `.reassigning` → `.done(result)`.
/// See `specs/duplicate-displayid-cleanup/design.md#datamaintenanceview-state-machine`.
struct DataMaintenanceView: View {
    @Environment(DisplayIDMaintenanceService.self) private var maintenanceService
    @Environment(\.resolvedTheme) fileprivate var resolvedTheme

    @State fileprivate var phase: Phase = .idle
    @State fileprivate var showConfirmAlert = false
    @State fileprivate var errorMessage: String?

    enum Phase {
        case idle
        case scanning
        case scanned(DuplicateReport)
        case reassigning
        case done(ReassignmentResult)
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    fileprivate var actionsRow: some View {
        HStack {
            Button { runScan() } label: {
                Label("Scan for duplicate display IDs", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("dataMaintenance.scanButton")
            .disabled(isBusy)

            Spacer()

            if showReassignButton {
                Button(role: .destructive) {
                    showConfirmAlert = true
                } label: {
                    Label("Reassign Losers", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("dataMaintenance.reassignButton")
                .disabled(isBusy)
            }
        }
    }

    fileprivate var progressRow: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(phaseLabel).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    fileprivate var confirmAlertButtons: some View {
        Button("Cancel", role: .cancel) {}
        Button("Reassign", role: .destructive) { runReassign() }
            .accessibilityIdentifier("dataMaintenance.confirmButton")
    }

    fileprivate var isBusy: Bool {
        switch phase {
        case .scanning, .reassigning: true
        default: false
        }
    }

    fileprivate var showReassignButton: Bool {
        if case .scanned(let report) = phase {
            return !report.tasks.isEmpty || !report.milestones.isEmpty
        }
        return false
    }

    private var phaseLabel: String {
        switch phase {
        case .scanning: "Scanning…"
        case .reassigning: "Reassigning…"
        default: ""
        }
    }

    fileprivate static let actionsFooter =
        "Scan finds tasks or milestones that share the same display ID. "
        + "Reassigning gives losers fresh IDs greater than any existing ID. "
        + "Reassigned tasks receive an audit comment."

    fileprivate static let confirmMessage =
        "This rewrites display IDs for losers in each duplicate group "
        + "and appends an audit comment to reassigned tasks. "
        + "This action cannot be undone."

    private func runScan() {
        phase = .scanning
        Task {
            do {
                let report = try maintenanceService.scanDuplicates()
                phase = .scanned(report)
            } catch {
                phase = .idle
                errorMessage = "Scan failed: \(error.localizedDescription)"
            }
        }
    }

    private func runReassign() {
        phase = .reassigning
        Task {
            let result = await maintenanceService.reassignDuplicates()
            phase = .done(result)
        }
    }
}

extension DataMaintenanceView {
    @ViewBuilder
    fileprivate func groupRow(_ group: DuplicateGroup, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(prefix)-\(group.displayId)").font(.headline)
            ForEach(group.records, id: \.id) { record in
                recordRow(record)
            }
        }
        .padding(.vertical, 4)
    }

    private func recordRow(_ record: RecordRef) -> some View {
        HStack(spacing: 8) {
            roleBadge(record.role)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                Text(record.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func roleBadge(_ role: RecordRole) -> some View {
        Text(role == .winner ? "Winner" : "Loser")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(role == .winner ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundStyle(role == .winner ? Color.green : Color.orange)
            .clipShape(Capsule())
    }

    @ViewBuilder
    fileprivate func resultGroupsList(_ result: ReassignmentResult) -> some View {
        if result.status == .busy {
            Text("Another maintenance run is already in progress.")
                .foregroundStyle(.secondary)
        } else if result.groups.isEmpty {
            Text("No groups required reassignment.")
                .foregroundStyle(.secondary)
        } else {
            // Composite key: tasks and milestones can share displayId values
            // (e.g. T-5 and M-5 both duplicated), so keying by displayId alone
            // produces SwiftUI diff collisions.
            ForEach(result.groups, id: \.stableID) { group in
                resultGroupRow(group)
            }
        }
    }

    private func resultGroupRow(_ group: GroupResult) -> some View {
        let prefix = group.type == .task ? "T" : "M"
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(prefix)-\(group.displayId) — \(group.winner.name)").font(.headline)
            if let failure = group.failure {
                Text("Failed: \(failure.code.rawValue) — \(failure.message)")
                    .font(.caption).foregroundStyle(.red)
            }
            ForEach(group.reassignments, id: \.id) { entry in
                reassignmentEntryRow(entry, prefix: prefix)
            }
        }
        .padding(.vertical, 4)
    }

    private func reassignmentEntryRow(_ entry: ReassignmentEntry, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.name): \(prefix)-\(entry.previousDisplayId) → \(prefix)-\(entry.newDisplayId)")
                .font(.subheadline)
            if let warning = entry.commentWarning {
                Text("Comment warning: \(warning)")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    fileprivate func counterAdvanceFooter(_ advance: CounterAdvanceResult?) -> some View {
        if let advance {
            VStack(alignment: .leading, spacing: 2) {
                if let task = advance.task {
                    Text("Task counter: \(formatCounterEntry(task))")
                }
                if let milestone = advance.milestone {
                    Text("Milestone counter: \(formatCounterEntry(milestone))")
                }
            }
        }
    }

    private func formatCounterEntry(_ entry: CounterAdvanceEntry) -> String {
        if let warning = entry.warning { return "warning — \(warning)" }
        if let advancedTo = entry.advancedTo { return "advanced to \(advancedTo)" }
        return "no change"
    }

    fileprivate var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#if os(iOS)
extension DataMaintenanceView {
    fileprivate var iOSLayout: some View {
        List {
            Section {
                actionsRow
            } header: {
                Text("Actions")
            } footer: {
                Text(Self.actionsFooter)
            }

            switch phase {
            case .idle:
                EmptyView()
            case .scanning, .reassigning:
                Section { progressRow }
            case .scanned(let report):
                reportSections(report)
            case .done(let result):
                resultSections(result)
            }
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle("Data Maintenance")
        .navigationBarTitleDisplayMode(.large)
        .alert("Reassign duplicate display IDs?", isPresented: $showConfirmAlert) {
            confirmAlertButtons
        } message: {
            Text(Self.confirmMessage)
        }
        .alert("Maintenance Failed", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    fileprivate func reportSections(_ report: DuplicateReport) -> some View {
        if report.tasks.isEmpty && report.milestones.isEmpty {
            Section {
                Text("No duplicate display IDs found.")
                    .foregroundStyle(.secondary)
            }
        } else {
            if !report.tasks.isEmpty {
                Section("Tasks") {
                    ForEach(report.tasks, id: \.displayId) { group in
                        groupRow(group, prefix: "T")
                    }
                }
            }
            if !report.milestones.isEmpty {
                Section("Milestones") {
                    ForEach(report.milestones, id: \.displayId) { group in
                        groupRow(group, prefix: "M")
                    }
                }
            }
        }
    }

    @ViewBuilder
    fileprivate func resultSections(_ result: ReassignmentResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                resultGroupsList(result)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dataMaintenance.resultList")
        } header: {
            Text("Result")
        } footer: {
            counterAdvanceFooter(result.counterAdvance)
        }
    }
}
#endif

#if os(macOS)
extension DataMaintenanceView {
    fileprivate var macOSLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiquidGlassSection(title: "Actions") {
                    VStack(alignment: .leading, spacing: 16) {
                        actionsRow
                        Text(Self.actionsFooter)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                switch phase {
                case .idle:
                    EmptyView()
                case .scanning, .reassigning:
                    LiquidGlassSection { progressRow }
                case .scanned(let report):
                    macOSReportSection(report)
                case .done(let result):
                    macOSResultSection(result)
                }
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle("Data Maintenance")
        .alert("Reassign duplicate display IDs?", isPresented: $showConfirmAlert) {
            confirmAlertButtons
        } message: {
            Text(Self.confirmMessage)
        }
        .alert("Maintenance Failed", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    fileprivate func macOSReportSection(_ report: DuplicateReport) -> some View {
        if report.tasks.isEmpty && report.milestones.isEmpty {
            LiquidGlassSection(title: "Report") {
                Text("No duplicate display IDs found.")
                    .foregroundStyle(.secondary)
            }
        } else {
            if !report.tasks.isEmpty {
                LiquidGlassSection(title: "Tasks") {
                    macOSGroupList(report.tasks, prefix: "T")
                }
            }
            if !report.milestones.isEmpty {
                LiquidGlassSection(title: "Milestones") {
                    macOSGroupList(report.milestones, prefix: "M")
                }
            }
        }
    }

    private func macOSGroupList(_ groups: [DuplicateGroup], prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(groups.enumerated()), id: \.element.displayId) { index, group in
                groupRow(group, prefix: prefix)
                if index < groups.count - 1 { Divider() }
            }
        }
    }

    @ViewBuilder
    fileprivate func macOSResultSection(_ result: ReassignmentResult) -> some View {
        LiquidGlassSection(title: "Result") {
            VStack(alignment: .leading, spacing: 12) {
                resultGroupsList(result)
                counterAdvanceFooter(result.counterAdvance)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dataMaintenance.resultList")
        }
    }
}
#endif
