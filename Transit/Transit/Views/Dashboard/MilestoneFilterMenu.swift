import SwiftUI

struct MilestoneFilterMenu: View {
    let projects: [Project]
    let selectedProjectIDs: Set<UUID>
    @Binding var selectedMilestones: Set<UUID>

    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showPopover = false

    private var availableMilestones: [Milestone] {
        Self.availableMilestones(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs,
            selectedMilestones: selectedMilestones,
            milestoneService: milestoneService
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
                    Text(milestoneTitle(for: milestone))
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
            .accessibilityLabel(milestoneAccessibilityLabel(for: milestone))
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

    private func milestoneTitle(for milestone: Milestone) -> String {
        selectedProjectIDs.count == 1 ? milestone.name : milestone.displayName
    }

    private func milestoneAccessibilityLabel(for milestone: Milestone) -> String {
        guard milestone.status.isTerminal else { return milestoneTitle(for: milestone) }
        let selection = selectedMilestones.contains(milestone.id) ? "selected" : "not selected"
        return "\(milestoneTitle(for: milestone)), \(milestone.status.displayName), \(selection)"
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
        projects: [Project],
        selectedProjectIDs: Set<UUID>,
        selectedMilestones: Set<UUID>,
        milestoneService: MilestoneService
    ) -> [Milestone] {
        let scopedProjects = scopedProjects(projects: projects, selectedProjectIDs: selectedProjectIDs)
        let accessibleMilestones = scopedProjects.flatMap { milestoneService.milestonesForProject($0) }
        let visibleIDs = visibleMilestoneIDs(
            openMilestoneIDs: accessibleMilestones.filter { $0.status == .open }.map(\.id),
            selectedAccessibleMilestoneIDs: accessibleMilestones.filter {
                selectedMilestones.contains($0.id)
            }.map(\.id)
        )
        return visibleIDs.compactMap { id in
            accessibleMilestones.first { $0.id == id }
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
