import SwiftUI

struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskService.self) private var taskService

    let projects: [Project]
    var onCreated: ((TransitTask) -> Void)?

    @State private var selectedProjectID: UUID?
    @State private var name = ""
    @State private var description = ""
    @State private var selectedType: TaskType = .feature
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedProject: Project? {
        guard let selectedProjectID else {
            return projects.first
        }
        return projects.first(where: { $0.id == selectedProjectID })
    }

    private var canCreateTask: Bool {
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
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTask()
                    }
                    .disabled(!canCreateTask)
                }
            }
            .task {
                if selectedProjectID == nil {
                    selectedProjectID = projects.first?.id
                }
            }
            .alert("Unable to Create Task", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var selectedProjectSelection: Binding<UUID?> {
        Binding(
            get: {
                selectedProjectID ?? projects.first?.id
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

    private func createTask() {
        guard !isSaving else {
            return
        }

        isSaving = true

        Task { @MainActor in
            defer { isSaving = false }

            do {
                guard let selectedProject else {
                    errorMessage = "Select a project before creating a task."
                    return
                }

                let task = try await taskService.createTask(
                    project: selectedProject,
                    name: name,
                    description: description,
                    type: selectedType
                )
                onCreated?(task)
                dismiss()
            } catch {
                errorMessage = "Transit could not create the task. Please try again."
            }
        }
    }
}

#Preview {
    AddTaskSheet(projects: [])
}
