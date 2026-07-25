import SwiftUI

extension TaskEditMerge {
    /// User-facing explanation of a save that ran into a concurrent write.
    var conflictDescription: String {
        let fields = conflictingFieldNames.joined(separator: ", ")
        return """
            These fields changed elsewhere while you were editing: \(fields). \
            An agent may have updated this task over MCP, or the change may have \
            synced from another device.

            Keep My Changes overwrites them. Use Updated Values loads the new \
            values into the form so you can review them. Your edits to other \
            fields are kept either way.
            """
    }
}

/// Asks the user how to resolve fields that both they and an external writer
/// changed while the editor was open.
///
/// Presented *instead of* saving: the editor has no basis for preferring one
/// version over the other, so neither is discarded without an explicit choice
/// (T-1798).
struct TaskEditConflictAlert: ViewModifier {
    @Binding var conflict: TaskEditMerge?
    let keepMine: () -> Void
    let useTheirs: (TaskEditMerge) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Task Changed Elsewhere",
            isPresented: Binding(
                get: { conflict != nil },
                set: { if !$0 { conflict = nil } }
            ),
            presenting: conflict
        ) { merge in
            Button("Keep My Changes", role: .destructive) { keepMine() }
            Button("Use Updated Values", role: .cancel) { useTheirs(merge) }
        } message: { merge in
            Text(merge.conflictDescription)
        }
    }
}

extension View {
    func taskEditConflictAlert(
        conflict: Binding<TaskEditMerge?>,
        keepMine: @escaping () -> Void,
        useTheirs: @escaping (TaskEditMerge) -> Void
    ) -> some View {
        modifier(
            TaskEditConflictAlert(conflict: conflict, keepMine: keepMine, useTheirs: useTheirs)
        )
    }
}
