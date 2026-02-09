//
//  ProjectEditView.swift
//  Transit
//
//  Project create/edit form with color picker.
//

import SwiftData
import SwiftUI

struct ProjectEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: Project?

    @State private var name: String
    @State private var projectDescription: String
    @State private var gitRepo: String
    @State private var selectedColor: Color
    @State private var showError = false

    init(project: Project?) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _projectDescription = State(initialValue: project?.projectDescription ?? "")
        _gitRepo = State(initialValue: project?.gitRepo ?? "")
        _selectedColor = State(initialValue: project?.color ?? .blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Project Name", text: $name)

                    TextField("Description (optional)", text: $projectDescription, axis: .vertical)
                        .lineLimit(2...4)

                    TextField("Git Repository (optional)", text: $gitRepo)
                }

                Section("Color") {
                    ColorPicker("Project Color", selection: $selectedColor)
                }
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Create" : "Save") {
                        saveProject()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("Failed to save project", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveProject() {
        guard canSave else {
            showError = true
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGitRepo = gitRepo.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let project = project {
                project.name = trimmedName
                project.projectDescription = trimmedDescription
                project.gitRepo = trimmedGitRepo.isEmpty ? nil : trimmedGitRepo
                project.colorHex = selectedColor.hexString
            } else {
                let newProject = Project(
                    name: trimmedName,
                    description: trimmedDescription,
                    gitRepo: trimmedGitRepo.isEmpty ? nil : trimmedGitRepo,
                    color: selectedColor
                )
                modelContext.insert(newProject)
            }

            try modelContext.save()
            dismiss()
        } catch {
            showError = true
        }
    }
}
