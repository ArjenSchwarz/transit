import SwiftUI

struct TaskDetailView: View {
    let task: TransitTask
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false

    var body: some View {
        NavigationStack {
            Form {
                detailSection
                descriptionSection
                MetadataSection(metadata: .constant(task.metadata), isEditing: false)
                actionSection
            }
            .navigationTitle(task.displayID.formatted)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showEdit = true }
                }
            }
            .sheet(isPresented: $showEdit) {
                TaskEditView(task: task)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var detailSection: some View {
        Section {
            LabeledContent("Name", value: task.name)
            LabeledContent("Type") { TypeBadge(type: task.type) }
            LabeledContent("Status", value: task.status.shortLabel)
            if let project = task.project {
                LabeledContent("Project") {
                    HStack {
                        ProjectColorDot(color: Color(hex: project.colorHex))
                        Text(project.name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let description = task.taskDescription, !description.isEmpty {
            Section("Description") {
                Text(description)
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        Section {
            if task.status == .abandoned {
                Button("Restore to Idea") {
                    try? taskService.restore(task: task)
                    dismiss()
                }
            } else {
                // Abandon from any status including Done [req 4.5]
                Button("Abandon", role: .destructive) {
                    try? taskService.abandon(task: task)
                    dismiss()
                }
            }
        }
    }
}
