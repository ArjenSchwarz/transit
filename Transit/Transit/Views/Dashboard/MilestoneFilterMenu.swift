import SwiftData
import SwiftUI

struct MilestoneFilterMenu: View {
    let projects: [Project]
    let selectedProjectIDs: Set<UUID>
    @Binding var selectedMilestones: Set<UUID>

    // Observe every milestone so local mutations, MCP calls, and CloudKit imports
    // refresh an already-presented menu. Project scoping stays in memory because
    // the dynamic selected-project set cannot be expressed by a CloudKit-safe
    // SwiftData predicate, while terminal selections must remain observable.
    @Query(sort: \Milestone.name) private var allMilestones: [Milestone]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showPopover = false

    private var availableMilestones: [Milestone] {
        Self.availableMilestones(
            milestones: allMilestones,
            projects: projects,
            selectedProjectIDs: selectedProjectIDs,
            selectedMilestones: selectedMilestones
        )
    }

    var body: some View {
        if Self.shouldShowMenu(
            availableMilestones: availableMilestones,
            selectedMilestones: selectedMilestones
        ) {
            Button { showPopover.toggle() } label: { filterLabel }
                .accessibilityIdentifier("dashboard.filter.milestones")
                .accessibilityLabel(Self.accessibilityLabel(for: selectedMilestones.count))
                #if os(macOS)
                .popover(isPresented: $showPopover) {
                    List {
                        Section {
                            toggleContent
                        }
                        clearSection
                    }
                    .frame(minWidth: 260, minHeight: 220)
                }
                #else
                .sheet(isPresented: $showPopover) {
                    NavigationStack {
                        List {
                            toggleContent
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
    private var toggleContent: some View {
        ForEach(availableMilestones) { milestone in
            Button {
                $selectedMilestones.contains(milestone.id).wrappedValue.toggle()
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

    static func shouldShowMenu(availableMilestones: [Milestone], selectedMilestones: Set<UUID>) -> Bool {
        !availableMilestones.isEmpty || !selectedMilestones.isEmpty
    }

    static func availableMilestones(
        milestones: [Milestone],
        projects: [Project],
        selectedProjectIDs: Set<UUID>,
        selectedMilestones: Set<UUID>
    ) -> [Milestone] {
        let scopedProjectIDs = Set(scopedProjects(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs
        ).map(\.id))
        let accessibleMilestones = orderedMilestones(
            milestones.filter { milestone in
                guard let projectID = milestone.project?.id else { return false }
                return scopedProjectIDs.contains(projectID)
            },
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

    private static func orderedMilestones(
        _ milestones: [Milestone],
        selectedProjectIDs: Set<UUID>
    ) -> [Milestone] {
        milestones.sorted { lhs, rhs in
            let titleOrder = milestoneTitle(
                for: lhs,
                selectedProjectIDs: selectedProjectIDs
            ).localizedCaseInsensitiveCompare(milestoneTitle(
                for: rhs,
                selectedProjectIDs: selectedProjectIDs
            ))
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
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
