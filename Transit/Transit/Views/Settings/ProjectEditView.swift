import SwiftData
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
    @State private var errorMessage: String?

    private var isEditing: Bool { project != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !projectDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        #if os(macOS)
        macOSForm
            .alert("Save Failed", isPresented: $errorMessage.isPresent) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        #else
        iOSForm
            .alert("Save Failed", isPresented: $errorMessage.isPresent) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        #endif
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSForm: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Description", text: $projectDescription, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Git Repo URL", text: $gitRepo)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }

            if let project {
                MilestoneListSection(project: project)
            }
        }
        .navigationTitle(isEditing ? "Edit Project" : "New Project")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { editToolbar }
        .onAppear { loadProject() }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private static let labelWidth: CGFloat = 90

    private var macOSForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiquidGlassSection(title: "Details") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
                        FormRow("Name", labelWidth: Self.labelWidth) {
                            TextField("", text: $name)
                        }

                        FormRow("Description", labelWidth: Self.labelWidth) {
                            TextField("", text: $projectDescription, axis: .vertical)
                                .lineLimit(3...6)
                        }

                        FormRow("Git Repo", labelWidth: Self.labelWidth) {
                            TextField("", text: $gitRepo)
                                .autocorrectionDisabled()
                        }
                    }
                }

                LiquidGlassSection(title: "Appearance") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
                        FormRow("Color", labelWidth: Self.labelWidth) {
                            ColorPicker("", selection: $color, supportsOpacity: false)
                                .labelsHidden()
                                .fixedSize()
                        }
                    }
                }

                if let project {
                    MilestoneListSection(project: project)
                }

                HStack {
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(isEditing ? "Edit Project" : "New Project")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .onAppear { loadProject() }
    }
    #endif

    // MARK: - Shared

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
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

    private func loadProject() {
        if let project {
            name = project.name
            projectDescription = project.projectDescription
            gitRepo = project.gitRepo ?? ""
            color = Color(hex: project.colorHex)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = projectDescription.trimmingCharacters(in: .whitespaces)
        let trimmedRepo = gitRepo.trimmingCharacters(in: .whitespaces)

        if let project {
            // When renaming, check for conflicts with other projects.
            if projectService.projectNameExists(trimmedName, excluding: project.id) {
                errorMessage = "A project named \"\(trimmedName)\" already exists."
                return
            }
            project.name = trimmedName
            project.projectDescription = trimmedDesc
            project.gitRepo = trimmedRepo.isEmpty ? nil : trimmedRepo
            project.colorHex = color.hexString
            do {
                try modelContext.save()
            } catch {
                // Rollback reverts the model to its last-persisted values. The @State
                // variables (name, projectDescription, etc.) are unaffected, so the form
                // keeps the user's in-progress edits for retry.
                modelContext.rollback()
                errorMessage = "Could not save project. Please try again."
                return
            }
        } else {
            do {
                try projectService.createProject(
                    name: trimmedName,
                    description: trimmedDesc,
                    gitRepo: trimmedRepo.isEmpty ? nil : trimmedRepo,
                    colorHex: color.hexString
                )
            } catch is ProjectMutationError {
                errorMessage = "A project named \"\(trimmedName)\" already exists."
                return
            } catch {
                errorMessage = "Failed to create project."
                return
            }
        }
        dismiss()
    }
}
