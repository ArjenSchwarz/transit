import SwiftData
import SwiftUI

struct TaskEditView: View {
    let task: TransitTask
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]

    @State private var name: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedType: TaskType = .feature
    @State private var selectedStatus: TaskStatus = .idea
    @State private var selectedProjectID: UUID?
    @State private var metadata: [String: String] = [:]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedProjectID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                fieldsSection
                statusSection
                MetadataSection(metadata: $metadata, isEditing: true)
            }
            .navigationTitle("Edit Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadTask() }
        }
    }

    // MARK: - Sections

    private var fieldsSection: some View {
        Section {
            TextField("Name", text: $name)

            TextField("Description", text: $taskDescription, axis: .vertical)
                .lineLimit(3...6)

            Picker("Type", selection: $selectedType) {
                ForEach(TaskType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            Picker("Project", selection: $selectedProjectID) {
                ForEach(projects) { project in
                    HStack {
                        ProjectColorDot(color: Color(hex: project.colorHex))
                        Text(project.name)
                    }
                    .tag(Optional(project.id))
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            Picker("Status", selection: $selectedStatus) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Text(status.rawValue).tag(status)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadTask() {
        name = task.name
        taskDescription = task.taskDescription ?? ""
        selectedType = task.type
        selectedStatus = task.status
        selectedProjectID = task.project?.id
        metadata = task.metadata
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        task.name = trimmedName

        let trimmedDesc = taskDescription.trimmingCharacters(in: .whitespaces)
        task.taskDescription = trimmedDesc.isEmpty ? nil : trimmedDesc

        task.type = selectedType
        task.metadata = metadata

        // Update project if changed
        if let newProjectID = selectedProjectID, task.project?.id != newProjectID {
            task.project = projects.first { $0.id == newProjectID }
        }

        // Status change goes through TaskService for side effects
        if selectedStatus != task.status {
            try? taskService.updateStatus(task: task, to: selectedStatus)
        }

        dismiss()
    }
}
