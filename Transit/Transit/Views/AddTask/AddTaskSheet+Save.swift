import SwiftData
import SwiftUI

// MARK: - Actions

extension AddTaskSheet {

    func save() async {
        guard let project = selectedProject else { return }
        let trimmedName = name.trimmedForFormInput()
        guard !trimmedName.isEmpty else { return }

        let description = taskDescription.trimmedForFormInput()
        let draft = TaskDraft(
            name: trimmedName,
            description: description.isEmpty ? nil : description,
            type: selectedType,
            priority: selectedPriority,
            projectID: project.id,
            milestone: selectedMilestone
        )

        isSaving = true
        defer { isSaving = false }

        do {
            try await Self.persist(
                draft: draft,
                taskService: taskService
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fields collected by the New Task form, ready to be persisted.
    struct TaskDraft {
        let name: String
        let description: String?
        let type: TaskType
        let priority: TaskPriority
        let projectID: UUID
        let milestone: Milestone?
    }

    /// Persists a new task and optional milestone as one aggregate. Extracted as a
    /// static helper because the SwiftUI view layer cannot be invoked directly
    /// from tests.
    static func persist(
        draft: TaskDraft,
        taskService: TaskService
    ) async throws {
        _ = try await taskService.createTask(
            name: draft.name,
            description: draft.description,
            type: draft.type,
            projectID: draft.projectID,
            priority: draft.priority,
            milestone: draft.milestone
        )
    }
}
