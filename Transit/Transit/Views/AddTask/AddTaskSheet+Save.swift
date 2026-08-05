import SwiftData
import SwiftUI

/// Ties the shared creation lifecycle to Add Task terminology at its call sites
/// and in the regression suite.
typealias AddTaskSaveLifecycle = CreateSaveLifecycle

// MARK: - Actions

extension AddTaskSheet {

    func save() {
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
        guard saveLifecycle.beginSave() else { return }

        let task = Task { @MainActor in
            do {
                try await Self.persist(draft: draft, taskService: taskService)
                try Task.checkCancellation()

                // Record success before dismissal so this view's resulting
                // disappearance cannot cancel an operation that persisted.
                guard saveLifecycle.completeSave() else { return }
                saveTask = nil
                dismiss()
            } catch is CancellationError {
                finishCancelledSave()
            } catch {
                if Task.isCancelled {
                    finishCancelledSave()
                } else {
                    saveLifecycle.completeFailure()
                    saveTask = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
        saveTask = task
    }

    func cancelSaveForDisappearance() {
        guard saveLifecycle.cancelForDisappearance() else { return }
        saveTask?.cancel()
    }

    func finishCancelledSave() {
        saveLifecycle.completeCancellation()
        saveTask = nil
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
