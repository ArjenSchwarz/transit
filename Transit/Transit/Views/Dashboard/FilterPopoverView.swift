import SwiftUI

struct FilterPopoverView: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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

                if !selectedProjectIDs.isEmpty {
                    Button("Clear", role: .destructive) {
                        selectedProjectIDs.removeAll()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
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
        .frame(minWidth: 200)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
