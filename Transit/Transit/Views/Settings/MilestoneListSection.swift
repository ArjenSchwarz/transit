import SwiftUI

struct MilestoneListSection: View {
    let project: Project
    @Environment(MilestoneService.self) private var milestoneService
    @State private var milestones: [Milestone] = []
    @State private var milestoneToDelete: Milestone?
    @State private var showDeleteAlert = false
    @State private var errorMessage: String?

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSContent: some View {
        Section {
            if milestones.isEmpty {
                Text("No milestones yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(milestones) { milestone in
                milestoneRow(milestone)
            }
        } header: {
            HStack {
                Text("Milestones")
                Spacer()
                NavigationLink(value: NavigationDestination.milestoneEdit(project: project, milestone: nil)) {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { loadMilestones() }
        .alert("Delete Milestone?", isPresented: $showDeleteAlert) {
            deleteAlertActions
        } message: {
            deleteAlertMessage
        }
        .alert("Error", isPresented: $errorMessage.isPresent) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSContent: some View {
        LiquidGlassSection(title: "Milestones") {
            VStack(alignment: .leading, spacing: 0) {
                if milestones.isEmpty {
                    Text("No milestones yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(milestones) { milestone in
                        milestoneRow(milestone)
                        if milestone.id != milestones.last?.id {
                            Divider()
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                NavigationLink(value: NavigationDestination.milestoneEdit(project: project, milestone: nil)) {
                    Label("Add Milestone", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .onAppear { loadMilestones() }
        .alert("Delete Milestone?", isPresented: $showDeleteAlert) {
            deleteAlertActions
        } message: {
            deleteAlertMessage
        }
        .alert("Error", isPresented: $errorMessage.isPresent) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    #endif

    // MARK: - Shared

    private func milestoneRow(_ milestone: Milestone) -> some View {
        HStack {
            NavigationLink(value: NavigationDestination.milestoneEdit(project: project, milestone: milestone)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.name)
                        Text(milestone.displayID.formatted(prefix: "M"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(milestone.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            statusMenu(for: milestone)

            Button(role: .destructive) {
                milestoneToDelete = milestone
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func statusMenu(for milestone: Milestone) -> some View {
        Menu {
            ForEach(MilestoneStatus.allCases, id: \.self) { status in
                Button(status.displayName) {
                    changeStatus(milestone, to: status)
                }
                .disabled(milestone.status == status)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var affectedTaskCount: Int {
        milestoneToDelete?.tasks?.count ?? 0
    }

    @ViewBuilder
    private var deleteAlertActions: some View {
        Button("Delete", role: .destructive) {
            if let milestone = milestoneToDelete {
                deleteMilestone(milestone)
            }
        }
        Button("Cancel", role: .cancel) {
            milestoneToDelete = nil
        }
    }

    @ViewBuilder
    private var deleteAlertMessage: some View {
        if affectedTaskCount > 0 {
            let suffix = affectedTaskCount == 1 ? "" : "s"
            Text("This will unassign \(affectedTaskCount) task\(suffix) from this milestone.")
        } else {
            Text("This milestone has no assigned tasks.")
        }
    }

    // MARK: - Actions

    private func loadMilestones() {
        milestones = milestoneService.milestonesForProject(project)
    }

    private func changeStatus(_ milestone: Milestone, to status: MilestoneStatus) {
        do {
            try milestoneService.updateStatus(milestone, to: status)
            loadMilestones()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMilestone(_ milestone: Milestone) {
        do {
            try milestoneService.deleteMilestone(milestone)
            loadMilestones()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
