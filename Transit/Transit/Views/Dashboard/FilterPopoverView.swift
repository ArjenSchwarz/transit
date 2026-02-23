import SwiftUI

struct FilterPopoverView: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>
    @Binding var selectedTypes: Set<TaskType>
    @Binding var selectedMilestones: Set<UUID>
    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.dismiss) private var dismiss

    private var hasAnyFilter: Bool {
        !selectedProjectIDs.isEmpty || !selectedTypes.isEmpty || !selectedMilestones.isEmpty
    }

    /// Open milestones scoped by project filter, or all open milestones if no project is filtered.
    private var availableMilestones: [Milestone] {
        let scopedProjects = selectedProjectIDs.isEmpty
            ? projects
            : projects.filter { selectedProjectIDs.contains($0.id) }
        return scopedProjects.flatMap { milestoneService.milestonesForProject($0, status: .open) }
    }

    /// Selected milestones that are no longer in the available (open) set — shown dimmed.
    private var staleMilestoneIDs: Set<UUID> {
        let availableIDs = Set(availableMilestones.map(\.id))
        return selectedMilestones.subtracting(availableIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(projects) { (project: Project) in
                        Button {
                            if selectedProjectIDs.contains(project.id) {
                                selectedProjectIDs.remove(project.id)
                            } else {
                                selectedProjectIDs.insert(project.id)
                            }
                        } label: {
                            HStack {
                                ProjectColorDot(color: Color(hex: project.colorHex))
                                Text(project.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedProjectIDs.contains(project.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Projects")
                        Spacer()
                        if !selectedProjectIDs.isEmpty {
                            Button("Clear") {
                                selectedProjectIDs.removeAll()
                            }
                            .font(.caption)
                        }
                    }
                }

                Section {
                    ForEach(TaskType.allCases, id: \.self) { taskType in
                        Button {
                            if selectedTypes.contains(taskType) {
                                selectedTypes.remove(taskType)
                            } else {
                                selectedTypes.insert(taskType)
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(taskType.tintColor)
                                    .frame(width: 12, height: 12)
                                Text(taskType.rawValue.capitalized)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTypes.contains(taskType) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("filter.type.\(taskType.rawValue)")
                    }
                } header: {
                    HStack {
                        Text("Types")
                        Spacer()
                        if !selectedTypes.isEmpty {
                            Button("Clear") {
                                selectedTypes.removeAll()
                            }
                            .font(.caption)
                        }
                    }
                }

                milestoneFilterSection

                if hasAnyFilter {
                    Section {
                        Button("Clear All", role: .destructive) {
                            selectedProjectIDs.removeAll()
                            selectedTypes.removeAll()
                            selectedMilestones.removeAll()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Filter")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 200, minHeight: 300)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: selectedProjectIDs) { _, _ in
            selectedMilestones.removeAll()
        }
    }

    // MARK: - Milestone Filter

    @ViewBuilder
    private var milestoneFilterSection: some View {
        let allDisplayed = availableMilestones + staleMilestonesForDisplay
        if !allDisplayed.isEmpty || !selectedMilestones.isEmpty {
            Section {
                ForEach(allDisplayed) { milestone in
                    let isStale = staleMilestoneIDs.contains(milestone.id)
                    Button {
                        if selectedMilestones.contains(milestone.id) {
                            selectedMilestones.remove(milestone.id)
                        } else {
                            selectedMilestones.insert(milestone.id)
                        }
                    } label: {
                        HStack {
                            Text(milestone.displayName)
                                .foregroundStyle(isStale ? .secondary : .primary)
                            Spacer()
                            if selectedMilestones.contains(milestone.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .opacity(isStale ? 0.5 : 1.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Milestones")
                    Spacer()
                    if !selectedMilestones.isEmpty {
                        Button("Clear") {
                            selectedMilestones.removeAll()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    /// Stale milestones that are selected but no longer in the open set.
    /// We need to fetch them to display their names.
    private var staleMilestonesForDisplay: [Milestone] {
        staleMilestoneIDs.compactMap { id in
            try? milestoneService.findByID(id)
        }
    }
}
