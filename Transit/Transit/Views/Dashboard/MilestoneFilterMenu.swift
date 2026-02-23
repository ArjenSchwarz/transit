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
                        toggleContent
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
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedMilestones.contains(milestone.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    static func accessibilityLabel(for count: Int) -> String {
        "Milestone filter, \(count) selected"
    }
}
