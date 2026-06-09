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
                taskService: taskService,
                milestoneService: milestoneService
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

    /// Persists a new task and optionally assigns a milestone. Extracted as a
    /// static helper because the SwiftUI view layer cannot be invoked directly
    /// from tests.
    ///
    /// When milestone assignment fails after `createTask` has already saved
    /// the task, the newly-created task is deleted before rethrowing so the
    /// operation is atomic from the user's perspective. Matches the cleanup
    /// pattern used by `CreateTaskIntent` and MCP `create_task` [T-558,
    /// T-855].
    static func persist(
        draft: TaskDraft,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) async throws {
        let task = try await taskService.createTask(
            name: draft.name,
            description: draft.description,
            type: draft.type,
            projectID: draft.projectID,
            priority: draft.priority
        )
        guard let milestone = draft.milestone else { return }
        do {
            try milestoneService.setMilestone(milestone, on: task)
        } catch {
            // Avoid leaving an orphaned task in the store when the milestone
            // cannot be attached. `deleteTask` is best-effort: if it also
            // fails we still surface the original assignment error.
            try? taskService.deleteTask(task)
            throw error
        }
    }
}
