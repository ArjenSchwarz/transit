import SwiftUI

struct ProjectEditView: View {
    let project: Project?
    @Environment(ProjectService.self) private var projectService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var projectDescription: String = ""
    @State private var gitRepo: String = ""
    @State private var color: Color = .blue

    private var isEditing: Bool { project != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !projectDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Description", text: $projectDescription, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Git Repo URL", text: $gitRepo)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            Section {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle(isEditing ? "Edit Project" : "New Project")
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
        .onAppear {
            if let project {
                name = project.name
                projectDescription = project.projectDescription
                gitRepo = project.gitRepo ?? ""
                color = Color(hex: project.colorHex)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = projectDescription.trimmingCharacters(in: .whitespaces)
        let trimmedRepo = gitRepo.trimmingCharacters(in: .whitespaces)

        if let project {
            project.name = trimmedName
            project.projectDescription = trimmedDesc
            project.gitRepo = trimmedRepo.isEmpty ? nil : trimmedRepo
            project.colorHex = color.hexString
            try? modelContext.save()
        } else {
            projectService.createProject(
                name: trimmedName,
                description: trimmedDesc,
                gitRepo: trimmedRepo.isEmpty ? nil : trimmedRepo,
                colorHex: color.hexString
            )
        }
        dismiss()
    }
}
