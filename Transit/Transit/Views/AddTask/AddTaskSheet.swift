//
//  AddTaskSheet.swift
//  Transit
//
//  Task creation sheet with project picker and validation.
//

import SwiftData
import SwiftUI

struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskService.self) private var taskService
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedProject: Project?
    @State private var name = ""
    @State private var taskDescription = ""
    @State private var selectedType: TaskType = .feature
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                if projects.isEmpty {
                    Section {
                        Text("No projects available. Create a project in Settings first.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Project") {
                        Picker("Project", selection: $selectedProject) {
                            ForEach(projects) { project in
                                HStack {
                                    ProjectColorDot(color: project.color, size: 16)
                                    Text(project.name)
                                }
                                .tag(project as Project?)
                            }
                        }
                    }

                    Section("Details") {
                        TextField("Task Name", text: $name)

                        TextField("Description (optional)", text: $taskDescription, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    Section("Type") {
                        Picker("Type", selection: $selectedType) {
                            ForEach(TaskType.allCases, id: \.self) { type in
                                Text(type.rawValue.capitalized)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("New Task")
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
                    Button("Create") {
                        createTask()
                    }
                    .disabled(!canCreate)
                }
            }
            .alert("Task name is required", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                if selectedProject == nil {
                    selectedProject = projects.first
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedProject != nil
    }

    private func createTask() {
        guard canCreate, let project = selectedProject else {
            showError = true
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await taskService.createTask(
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    type: selectedType,
                    project: project,
                    metadata: nil
                )
                dismiss()
            } catch {
                showError = true
            }
        }
    }
}
