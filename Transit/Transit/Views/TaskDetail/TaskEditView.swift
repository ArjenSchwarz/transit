import SwiftData
import SwiftUI

struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskService.self) private var taskService

    let task: TransitTask
    let projects: [Project]

    @State private var name: String
    @State private var description: String
    @State private var selectedType: TaskType
    @State private var selectedStatus: TaskStatus
    @State private var selectedProjectID: UUID?
    @State private var metadata: [String: String]?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(task: TransitTask, projects: [Project]) {
        self.task = task
        self.projects = projects

        _name = State(initialValue: task.name)
        _description = State(initialValue: task.taskDescription ?? "")
        _selectedType = State(initialValue: task.type)
        _selectedStatus = State(initialValue: task.status)
        _selectedProjectID = State(initialValue: task.project?.id)
        _metadata = State(initialValue: task.metadata)
    }

    private var selectedProject: Project? {
        guard let selectedProjectID else {
            return projects.first
        }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && selectedProject != nil
        && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    Picker("Project", selection: selectedProjectSelection) {
                        ForEach(projects, id: \.id) { project in
                            HStack(spacing: 8) {
                                ProjectColorDot(color: project.color)
                                Text(project.name)
                            }
                            .tag(Optional(project.id))
                        }
                    }

                    TextField("Name", text: $name)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)

                    Picker("Type", selection: $selectedType) {
                        ForEach(TaskType.allCases, id: \.self) { type in
                            Text(type.badgeTitle).tag(type)
                        }
                    }

                    Picker("Status", selection: $selectedStatus) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(statusPickerTitle(for: status)).tag(status)
                        }
                    }
                }

                MetadataSection(metadata: $metadata)
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                    }
                    .disabled(!canSave)
                }
            }
            .task {
                if selectedProjectID == nil {
                    selectedProjectID = task.project?.id ?? projects.first?.id
                }
            }
            .alert("Unable to Save Changes", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var selectedProjectSelection: Binding<UUID?> {
        Binding(
            get: {
                selectedProjectID ?? task.project?.id ?? projects.first?.id
            },
            set: { selectedProjectID = $0 }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func statusPickerTitle(for status: TaskStatus) -> String {
        switch status {
        case .idea:
            return "Idea"
        case .planning:
            return "Planning"
        case .spec:
            return "Spec"
        case .readyForImplementation:
            return "Ready for Implementation"
        case .inProgress:
            return "In Progress"
        case .readyForReview:
            return "Ready for Review"
        case .done:
            return "Done"
        case .abandoned:
            return "Abandoned"
        }
    }

    private func saveTask() {
        guard !isSaving else {
            return
        }

        isSaving = true

        Task { @MainActor in
            defer { isSaving = false }

            do {
                guard let selectedProject else {
                    errorMessage = "Select a project before saving."
                    return
                }

                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else {
                    errorMessage = "Task name is required."
                    return
                }

                task.name = trimmedName
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                task.taskDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
                task.type = selectedType
                task.project = selectedProject
                task.metadata = metadata

                if task.status != selectedStatus {
                    try taskService.updateStatus(task: task, to: selectedStatus)
                } else {
                    try modelContext.save()
                }

                dismiss()
            } catch {
                errorMessage = "Transit could not save the task changes. Please try again."
            }
        }
    }
}

#Preview {
    Text("TaskEditView Preview")
}
