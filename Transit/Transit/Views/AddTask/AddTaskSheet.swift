import SwiftData
import SwiftUI

struct AddTaskSheet: View {
    @Environment(TaskService.self) private var taskService
    @Environment(ProjectService.self) private var projectService
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]

    @State private var name = ""
    @State private var taskDescription = ""
    @State private var selectedType: TaskType = .feature
    @State private var selectedProjectID: UUID?

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedProject != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    EmptyStateView(message: "No projects yet. Create one in Settings.")
                } else {
                    taskForm
                }
            }
            .navigationTitle("New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
        }
    }

    // MARK: - Form

    private var taskForm: some View {
        Form {
            Section {
                Picker("Project", selection: $selectedProjectID) {
                    ForEach(projects) { project in
                        HStack {
                            ProjectColorDot(color: Color(hex: project.colorHex))
                            Text(project.name)
                        }
                        .tag(Optional(project.id))
                    }
                }

                TextField("Name", text: $name)

                TextField("Description", text: $taskDescription, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Picker("Type", selection: $selectedType) {
                    ForEach(TaskType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let project = selectedProject else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let description = taskDescription.trimmingCharacters(in: .whitespaces)

        Task {
            try await taskService.createTask(
                name: trimmedName,
                description: description.isEmpty ? nil : description,
                type: selectedType,
                project: project
            )
            dismiss()
        }
    }
}
