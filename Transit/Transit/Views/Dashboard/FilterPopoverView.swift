import SwiftUI

struct FilterPopoverView: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Projects")
                    .font(.headline)

                Spacer(minLength: 8)

                Button("Clear") {
                    selectedProjectIDs.removeAll(keepingCapacity: true)
                }
                .disabled(selectedProjectIDs.isEmpty)
            }

            if projects.isEmpty {
                EmptyStateView(message: "No projects yet", symbol: "folder")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(projects, id: \.id) { project in
                            Button {
                                toggle(projectID: project.id)
                            } label: {
                                HStack(spacing: 10) {
                                    let isSelected = selectedProjectIDs.contains(project.id)
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                                    ProjectColorDot(color: project.color)

                                    Text(project.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 260)
            }
        }
        .padding(14)
        .frame(minWidth: 280)
        .glassEffect()
    }

    private func toggle(projectID: UUID) {
        if selectedProjectIDs.contains(projectID) {
            selectedProjectIDs.remove(projectID)
        } else {
            selectedProjectIDs.insert(projectID)
        }
    }
}
