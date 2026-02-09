import SwiftUI

struct FilterPopoverView: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if !selectedProjectIDs.isEmpty {
                Divider()
                Button("Clear", role: .destructive) {
                    selectedProjectIDs.removeAll()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 200)
        .padding(.vertical, 8)
    }
}
