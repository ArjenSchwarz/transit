import SwiftData
import SwiftUI

struct ProjectEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProjectService.self) private var projectService

    let project: Project?

    @State private var name: String
    @State private var description: String
    @State private var gitRepo: String
    @State private var color: Color
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(project: Project?) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _description = State(initialValue: project?.projectDescription ?? "")
        _gitRepo = State(initialValue: project?.gitRepo ?? "")
        _color = State(initialValue: project?.color ?? .accentColor)
    }

    private var isEditing: Bool {
        project != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isSaving
    }

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $name)

                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...8)

                TextField("Git Repo URL (optional)", text: $gitRepo)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
#endif

                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle(isEditing ? "Edit Project" : "New Project")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProject()
                }
                .disabled(!canSave)
            }
        }
        .alert("Unable to Save Project", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
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

    private func saveProject() {
        guard !isSaving else {
            return
        }

        isSaving = true

        Task { @MainActor in
            defer { isSaving = false }

            do {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedRepo = gitRepo.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedRepo = trimmedRepo.isEmpty ? nil : trimmedRepo

                if let project {
                    project.name = trimmedName
                    project.projectDescription = trimmedDescription
                    project.gitRepo = normalizedRepo
                    project.color = color
                    try modelContext.save()
                } else {
                    _ = try projectService.createProject(
                        name: trimmedName,
                        description: trimmedDescription,
                        gitRepo: normalizedRepo,
                        color: color
                    )
                }

                dismiss()
            } catch ProjectService.Error.invalidName {
                errorMessage = "Project name is required."
            } catch ProjectService.Error.invalidDescription {
                errorMessage = "Project description is required."
            } catch {
                errorMessage = "Transit could not save the project. Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProjectEditView(project: nil)
    }
}
