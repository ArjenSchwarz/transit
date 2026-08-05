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

                // TaskService checks cancellation immediately before insertion.
                // Both this continuation and `onDisappear` run on MainActor with
                // no suspension here, so a returning persist is committed success.
                // Record it before dismissal so disappearance cannot cancel it.
                guard saveLifecycle.completeSave() else {
                    assertionFailure("Persisted Add Task must still own its save lifecycle")
                    return
                }
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
