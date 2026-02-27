import SwiftData
import SwiftUI

struct ReportView: View {
    @Query(filter: #Predicate<TransitTask> {
        $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
    }) private var terminalTasks: [TransitTask]

    @Query(filter: #Predicate<Milestone> {
        $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
    }) private var terminalMilestones: [Milestone]

    @State private var selectedRange: ReportDateRange = .thisWeek
    @State private var showCopyConfirmation = false
    @Environment(\.resolvedTheme) private var resolvedTheme

    var body: some View {
        let report = ReportLogic.buildReport(
            tasks: terminalTasks,
            milestones: terminalMilestones,
            dateRange: selectedRange
        )

        ScrollView {
            if report.isEmpty {
                emptyState
            } else {
                reportContent(report)
            }
        }
        #if os(macOS)
        .scrollContentBackground(.hidden)
        #endif
        .background {
            BoardBackground(theme: resolvedTheme)
        }
        .navigationTitle("Report")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Date Range", selection: $selectedRange) {
                        ForEach(ReportDateRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(selectedRange.label, systemImage: "calendar")
                }
                .accessibilityIdentifier("report.dateRangePicker")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copyToClipboard(report)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("report.copyButton")
            }
        }
        .overlay(alignment: .top) {
            if showCopyConfirmation {
                copyConfirmationBanner
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Tasks",
            systemImage: "chart.bar.doc.horizontal",
            description: Text("No tasks completed or abandoned in this period.")
        )
        .accessibilityIdentifier("report.emptyState")
    }

    // MARK: - Report Content

    private func reportContent(_ report: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            summarySection(report)

            ForEach(report.projectGroups) { group in
                projectSection(group)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private func summarySection(_ report: ReportData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.dateRangeLabel)
                .font(.title2)
                .fontWeight(.bold)

            Text(ReportData.summaryText(done: report.totalDone, abandoned: report.totalAbandoned))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func projectSection(_ group: ProjectGroup) -> some View {
        LiquidGlassSection(title: group.projectName) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ReportData.summaryText(done: group.doneCount, abandoned: group.abandonedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !group.milestones.isEmpty {
                    ForEach(group.milestones) { milestone in
                        milestoneRow(milestone)
                    }

                    Divider()
                }

                ForEach(group.tasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func milestoneRow(_ milestone: ReportMilestone) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(milestone.displayID)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if milestone.isAbandoned {
                Text(milestone.name)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text("(Abandoned)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(milestone.name)
                    .fontWeight(.medium)
            }

            Text("\(milestone.taskCount) tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func taskRow(_ task: ReportTask) -> some View {
        HStack(spacing: 6) {
            Text(task.displayID)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            TypeBadge(type: task.taskType)

            if task.isAbandoned {
                Text(task.name)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text("(Abandoned)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(task.name)
            }
        }
    }

    // MARK: - Copy Confirmation

    private var copyConfirmationBanner: some View {
        Text("Copied to clipboard")
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    showCopyConfirmation = false
                }
            }
    }

    // MARK: - Helpers

    private func copyToClipboard(_ report: ReportData) {
        let markdown = ReportMarkdownFormatter.format(report)
        #if os(iOS)
        UIPasteboard.general.string = markdown
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif

        withAnimation {
            showCopyConfirmation = true
        }
    }
}
