import Foundation

extension TaskEditView {

    /// Resolves the picker ID against the observed project models immediately
    /// before Save, because a remote delete can leave the ID behind.
    var projectSelectionState: TaskEditProjectSelectionState {
        TaskEditProjectSelectionState(
            selectedProjectID: selectedProjectID,
            resolvedProjectID: selectedProject?.id
        )
    }
}
