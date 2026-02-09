//
//  TaskDetailView.swift
//  Transit
//
//  Read-only task detail view with Abandon/Restore actions.
//

import SwiftData
import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskService.self) private var taskService
    let task: TransitTask

    @State private var showEdit = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Display ID") {
                        Text(task.displayID.formatted)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Name") {
                        Text(task.name)
                    }

                    LabeledContent("Type") {
                        TypeBadge(type: task.type)
                    }

                    LabeledContent("Status") {
                        Text(task.status.shortLabel)
                            .foregroundStyle(.secondary)
                    }

                    if let project = task.project {
                        LabeledContent("Project") {
                            HStack {
                                ProjectColorDot(color: project.color, size: 16)
                                Text(project.name)
                            }
                        }
                    }
                }

                if let description = task.taskDescription, !description.isEmpty {
                    Section("Description") {
                        Text(description)
                    }
                }

                if !task.metadata.isEmpty {
                    Section("Metadata") {
                        ForEach(Array(task.metadata.keys.sorted()), id: \.self) { key in
                            if let value = task.metadata[key] {
                                LabeledContent(key) {
                                    Text(value)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showEdit = true
                    }
                }

                ToolbarItem(placement: .destructiveAction) {
                    if task.status == .abandoned {
                        Button("Restore") {
                            restoreTask()
                        }
                    } else {
                        Button("Abandon", role: .destructive) {
                            abandonTask()
                        }
                    }
                }
            }
            .alert("Failed to update task", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showEdit) {
                TaskEditView(task: task)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func abandonTask() {
        do {
            try taskService.abandon(task: task)
            dismiss()
        } catch {
            showError = true
        }
    }

    private func restoreTask() {
        do {
            try taskService.restore(task: task)
            dismiss()
        } catch {
            showError = true
        }
    }
}
