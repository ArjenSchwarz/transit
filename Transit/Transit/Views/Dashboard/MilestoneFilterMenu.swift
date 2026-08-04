import SwiftData
import SwiftUI

struct MilestoneFilterMenu: View {
    let projects: [Project]
    let selectedProjectIDs: Set<UUID>
    @Binding var selectedMilestones: Set<UUID>

    // Load-bearing observation: do not replace this with a service snapshot.
    // It refreshes an already-presented menu after local, MCP, or CloudKit changes.
    // Project scoping stays in memory because the dynamic selected-project set cannot
    // be expressed by a CloudKit-safe SwiftData predicate while retaining terminal rows.
    @Query private var allMilestones: [Milestone]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showPopover = false

    private var milestoneOptions: [Milestone] {
        Self.availableMilestones(
            milestones: allMilestones,
            projects: projects,
            selectedProjectIDs: selectedProjectIDs,
            selectedMilestones: selectedMilestones
        )
    }

    private var hasVisibleMilestoneOption: Bool {
        Self.hasVisibleMilestoneOption(
            milestones: allMilestones,
            projects: projects,
            selectedProjectIDs: selectedProjectIDs
        )
    }

    var body: some View {
        if Self.shouldShowMenu(
            hasVisibleMilestoneOption: hasVisibleMilestoneOption,
            selectedMilestones: selectedMilestones,
            isPresented: showPopover
        ) {
            Button { showPopover.toggle() } label: { filterLabel }
                .accessibilityIdentifier("dashboard.filter.milestones")
                .accessibilityLabel(Self.accessibilityLabel(for: selectedMilestones.count))
                .onChange(of: hasVisibleMilestoneOption) {
                    if showPopover && Self.shouldDismissPresentation(
                        hasVisibleMilestoneOption: hasVisibleMilestoneOption,
                        selectedMilestones: selectedMilestones
                    ) {
                        showPopover = false
                    }
                }
                #if os(macOS)
                .popover(isPresented: $showPopover) {
                    List {
                        Section {
                            toggleContent(milestoneOptions)
                        }
                        clearSection
                    }
                    .frame(minWidth: 260, minHeight: 220)
                }
                #else
                .sheet(isPresented: $showPopover) {
                    NavigationStack {
                        List {
                            toggleContent(milestoneOptions)
                            clearSection
                        }
                        .navigationTitle("Milestones")
                        .toolbarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showPopover = false }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
                #endif
        }
    }

    @ViewBuilder
    private func toggleContent(_ milestones: [Milestone]) -> some View {
        ForEach(milestones) { milestone in
            Button {
                $selectedMilestones.contains(milestone.id).wrappedValue.toggle()
                if Self.shouldDismissPresentation(
                    hasVisibleMilestoneOption: hasVisibleMilestoneOption,
                    selectedMilestones: selectedMilestones
                ) {
                    showPopover = false
                }
            } label: {
                HStack {
                    Text(Self.milestoneTitle(for: milestone, selectedProjectIDs: selectedProjectIDs))
                        .strikethrough(milestone.status.isTerminal)
                        .foregroundStyle(milestone.status.isTerminal ? .secondary : .primary)
                    if milestone.status.isTerminal {
                        Label(
                            milestone.status.displayName,
                            systemImage: milestone.status == .done ? "checkmark.circle" : "xmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedMilestones.contains(milestone.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.milestoneAccessibilityLabel(
                for: milestone,
                selectedProjectIDs: selectedProjectIDs
            ))
            .accessibilityAddTraits(selectedMilestones.contains(milestone.id) ? .isSelected : [])
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !selectedMilestones.isEmpty {
            Section {
                Button("Clear", role: .destructive) {
                    selectedMilestones.removeAll()
                    if Self.shouldDismissPresentation(
                        hasVisibleMilestoneOption: hasVisibleMilestoneOption,
                        selectedMilestones: selectedMilestones
                    ) {
                        showPopover = false
                    }
                }
            }
        }
    }

    static func milestoneTitle(for milestone: Milestone, selectedProjectIDs: Set<UUID>) -> String {
        selectedProjectIDs.count == 1 ? milestone.name : milestone.displayName
    }

    static func milestoneAccessibilityLabel(
        for milestone: Milestone,
        selectedProjectIDs: Set<UUID>
    ) -> String {
        let title = milestoneTitle(for: milestone, selectedProjectIDs: selectedProjectIDs)
        guard milestone.status.isTerminal else { return title }
        return "\(title), \(milestone.status.displayName)"
    }

    @ViewBuilder
    private var filterLabel: some View {
        let count = selectedMilestones.count
        if sizeClass == .compact {
            Image(systemName: count > 0 ? "flag.fill" : "flag")
                .badge(count)
        } else {
            Label(
                count > 0 ? "Milestones (\(count))" : "Milestones",
                systemImage: count > 0 ? "flag.fill" : "flag"
            )
        }
    }

    static func shouldShowMenu(
        hasVisibleMilestoneOption: Bool,
        selectedMilestones: Set<UUID>,
        isPresented: Bool = false
    ) -> Bool {
        isPresented || hasVisibleMilestoneOption || !selectedMilestones.isEmpty
    }

    static func shouldDismissPresentation(
        hasVisibleMilestoneOption: Bool,
        selectedMilestones: Set<UUID>
    ) -> Bool {
        !hasVisibleMilestoneOption && selectedMilestones.isEmpty
    }

    static func hasVisibleMilestoneOption(
        milestones: [Milestone],
        projects: [Project],
        selectedProjectIDs: Set<UUID>
    ) -> Bool {
        let scopedProjectIDs = scopedProjectIDs(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs
        )
        return milestones.contains { milestone in
            isAccessible(milestone, in: scopedProjectIDs) && milestone.status == .open
        }
    }

    static func availableMilestones(
        milestones: [Milestone],
        projects: [Project],
        selectedProjectIDs: Set<UUID>,
        selectedMilestones: Set<UUID>
    ) -> [Milestone] {
        let scopedProjectIDs = scopedProjectIDs(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs
        )
        let accessibleMilestones = orderedMilestones(
            milestones.filter { isAccessible($0, in: scopedProjectIDs) },
            selectedProjectIDs: selectedProjectIDs
        )
        let visibleIDs = visibleMilestoneIDs(
            openMilestoneIDs: accessibleMilestones.filter { $0.status == .open }.map(\.id),
            selectedAccessibleMilestoneIDs: accessibleMilestones.filter {
                selectedMilestones.contains($0.id)
            }.map(\.id)
        )
        let milestonesByID = Dictionary(
            accessibleMilestones.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return visibleIDs.compactMap { milestonesByID[$0] }
    }

    private static func scopedProjectIDs(
        projects: [Project],
        selectedProjectIDs: Set<UUID>
    ) -> Set<UUID> {
        Set(scopedProjects(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs
        ).map(\.id))
    }

    private static func isAccessible(_ milestone: Milestone, in projectIDs: Set<UUID>) -> Bool {
        guard let projectID = milestone.project?.id else { return false }
        return projectIDs.contains(projectID)
    }

    private static func orderedMilestones(
        _ milestones: [Milestone],
        selectedProjectIDs: Set<UUID>
    ) -> [Milestone] {
        let titledMilestones = milestones.map {
            (title: milestoneTitle(for: $0, selectedProjectIDs: selectedProjectIDs), milestone: $0)
        }
        return titledMilestones.sorted { lhs, rhs in
            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.milestone.id.uuidString < rhs.milestone.id.uuidString
        }.map(\.milestone)
    }

    nonisolated static func visibleMilestoneIDs(
        openMilestoneIDs: [UUID],
        selectedAccessibleMilestoneIDs: [UUID]
    ) -> [UUID] {
        var seen = Set<UUID>()
        return (openMilestoneIDs + selectedAccessibleMilestoneIDs).filter { seen.insert($0).inserted }
    }

    static func scopedProjects(projects: [Project], selectedProjectIDs: Set<UUID>) -> [Project] {
        guard !selectedProjectIDs.isEmpty else { return projects }
        return projects.filter { selectedProjectIDs.contains($0.id) }
    }

    static func accessibilityLabel(for count: Int) -> String {
        "Milestone filter, \(count) selected"
    }
}
