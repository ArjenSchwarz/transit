import SwiftUI

struct MilestoneFilterMenu: View {
    let projects: [Project]
    let selectedProjectIDs: Set<UUID>
    @Binding var selectedMilestones: Set<UUID>

    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.horizontalSizeClass) private var sizeClass

    #if os(macOS)
    @State private var showPopover = false
    #endif

    private var availableMilestones: [Milestone] {
        Self.availableMilestones(
            projects: projects,
            selectedProjectIDs: selectedProjectIDs,
            milestoneService: milestoneService
        )
    }

    var body: some View {
        if Self.shouldShowMenu(
            availableMilestones: availableMilestones,
            selectedMilestones: selectedMilestones
        ) {
            menuContent
                .accessibilityIdentifier("dashboard.filter.milestones")
                .accessibilityLabel(Self.accessibilityLabel(for: selectedMilestones.count))
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        #if os(macOS)
        Button { showPopover.toggle() } label: { filterLabel }
            .popover(isPresented: $showPopover) {
                List {
                    toggleContent
                    clearSection
                }
                .frame(minWidth: 260, minHeight: 220)
            }
        #else
        Menu {
            Section {
                toggleContent
            }
            .menuActionDismissBehavior(.disabled)

            clearSection
        } label: {
            filterLabel
        }
        #endif
    }

    @ViewBuilder
    private var toggleContent: some View {
        ForEach(availableMilestones) { milestone in
            Toggle(milestoneTitle(for: milestone), isOn: toggleBinding(for: milestone.id))
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !selectedMilestones.isEmpty {
            Section {
                Button("Clear", role: .destructive) {
                    Self.clear(&selectedMilestones)
                }
            }
        }
    }

    private func toggleBinding(for milestoneID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedMilestones.contains(milestoneID) },
            set: { isOn in
                Self.setSelection(isOn, for: milestoneID, in: &selectedMilestones)
            }
        )
    }

    private func milestoneTitle(for milestone: Milestone) -> String {
        selectedProjectIDs.count == 1 ? milestone.name : milestone.displayName
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
        milestoneService: MilestoneService
    ) -> [Milestone] {
        let scopedProjects = scopedProjects(projects: projects, selectedProjectIDs: selectedProjectIDs)
        return scopedProjects.flatMap { milestoneService.milestonesForProject($0, status: .open) }
    }

    static func scopedProjects(projects: [Project], selectedProjectIDs: Set<UUID>) -> [Project] {
        guard !selectedProjectIDs.isEmpty else { return projects }
        return projects.filter { selectedProjectIDs.contains($0.id) }
    }

    static func setSelection(_ isSelected: Bool, for milestoneID: UUID, in selectedMilestones: inout Set<UUID>) {
        if isSelected {
            selectedMilestones.insert(milestoneID)
        } else {
            selectedMilestones.remove(milestoneID)
        }
    }

    static func clear(_ selectedMilestones: inout Set<UUID>) {
        selectedMilestones.removeAll()
    }

    static func accessibilityLabel(for count: Int) -> String {
        "Milestone filter, \(count) selected"
    }
}
