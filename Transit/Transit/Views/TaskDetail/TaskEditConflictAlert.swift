import SwiftUI

extension EditMerge where Snapshot == TaskEditSnapshot {
    /// User-facing explanation of a save that ran into a concurrent write.
    var conflictDescription: String {
        conflictDescription(subject: "Task")
    }
}

extension View {
    /// The task editor's conflict alert. The behaviour — block the save, name
    /// the fields, offer keep-mine or load-theirs — is `EditConflictAlert`,
    /// shared with the project and milestone editors (T-1798, T-1817).
    func taskEditConflictAlert(
        conflict: Binding<TaskEditMerge?>,
        keepMine: @escaping () -> Void,
        useTheirs: @escaping (TaskEditMerge) -> Void
    ) -> some View {
        editConflictAlert(
            subject: "Task",
            conflict: conflict,
            keepMine: keepMine,
            useTheirs: useTheirs
        )
    }
}
