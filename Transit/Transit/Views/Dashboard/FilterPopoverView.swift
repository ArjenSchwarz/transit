import SwiftUI

struct FilterPopoverView: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>
    @Binding var selectedTypes: Set<TaskType>
    @Environment(\.dismiss) private var dismiss

    private var hasAnyFilter: Bool {
        !selectedProjectIDs.isEmpty || !selectedTypes.isEmpty
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

                if hasAnyFilter {
                    Section {
                        Button("Clear All", role: .destructive) {
                            selectedProjectIDs.removeAll()
                            selectedTypes.removeAll()
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
    }
}
