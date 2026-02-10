import SwiftData
import SwiftUI

struct TaskDetailView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: [SortDescriptor(\Project.name)])
    private var projects: [Project]

    let task: TransitTask

    @State private var isPresentingEdit = false
    @State private var errorMessage: String?

    private var statusTitle: String {
        switch task.status {
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Overview") {
                    detailRow("Display ID", value: task.displayID.formatted)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Name")
                        Spacer(minLength: 12)
                        Text(task.name)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Type")
                        Spacer(minLength: 12)
                        TypeBadge(type: task.type)
                    }

                    detailRow("Status", value: statusTitle)

                    HStack(alignment: .center) {
                        Text("Project")
                        Spacer(minLength: 12)
                        HStack(spacing: 8) {
                            ProjectColorDot(color: task.project?.color ?? .secondary.opacity(0.35))
                            Text(task.project?.name ?? "Unknown Project")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Description") {
                    if let taskDescription = task.taskDescription, !taskDescription.isEmpty {
                        Text(taskDescription)
                    } else {
                        EmptyStateView(message: "No description")
                    }
                }

                MetadataSection(metadata: task.metadata)

                Section("Dates") {
                    detailRow("Last Status Change", value: formatted(date: task.lastStatusChangeDate) ?? "-")
                    detailRow("Completion", value: formatted(date: task.completionDate) ?? "-")
                }

                Section {
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
            .navigationTitle(task.displayID.formatted)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        isPresentingEdit = true
                    }
                    .disabled(projects.isEmpty)
                }
            }
            .alert("Unable to Update Task", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .sheet(isPresented: $isPresentingEdit) {
                if horizontalSizeClass == .compact {
                    TaskEditView(task: task, projects: projects)
                        .presentationDragIndicator(.visible)
                        .presentationDetents([.large])
                } else {
                    TaskEditView(task: task, projects: projects)
                }
            }
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

    @ViewBuilder
    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatted(date: Date?) -> String? {
        guard let date else {
            return nil
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func abandonTask() {
        do {
            try taskService.abandon(task: task)
        } catch {
            errorMessage = "Transit could not abandon this task."
        }
    }

    private func restoreTask() {
        do {
            try taskService.restore(task: task)
        } catch {
            errorMessage = "Transit could not restore this task."
        }
    }
}

#Preview {
    Text("TaskDetailView Preview")
}
