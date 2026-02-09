//
//  TaskEditView.swift
//  Transit
//
//  Editable task view with status picker and metadata editing.
//

import SwiftData
import SwiftUI

struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskService.self) private var taskService
    @Query(sort: \Project.name) private var projects: [Project]

    let task: TransitTask

    @State private var name: String
    @State private var taskDescription: String
    @State private var selectedType: TaskType
    @State private var selectedProject: Project?
    @State private var selectedStatus: TaskStatus
    @State private var metadata: [String: String]
    @State private var showError = false

    init(task: TransitTask) {
        self.task = task
        _name = State(initialValue: task.name)
        _taskDescription = State(initialValue: task.taskDescription ?? "")
        _selectedType = State(initialValue: task.type)
        _selectedProject = State(initialValue: task.project)
        _selectedStatus = State(initialValue: task.status)
        _metadata = State(initialValue: task.metadata)
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Status") {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Text(status.shortLabel)
                                .tag(status)
                        }
                    }
                }

                Section {
                    MetadataSection(metadata: $metadata, isEditing: true)
                }
            }
            .navigationTitle("Edit Task")
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
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("Failed to save changes", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedProject != nil
    }

    private func saveChanges() {
        guard canSave, let project = selectedProject else {
            showError = true
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            task.name = trimmedName
            task.taskDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
            task.type = selectedType
            task.project = project
            task.metadata = metadata

            if task.status != selectedStatus {
                try taskService.updateStatus(task: task, to: selectedStatus)
            }

            try modelContext.save()
            dismiss()
        } catch {
            showError = true
        }
    }
}
