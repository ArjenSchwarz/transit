import SwiftUI

extension EditMerge {
    /// User-facing explanation of a save that ran into a concurrent write.
    ///
    /// - Parameter subject: the edited thing, capitalised ("Task", "Project").
    func conflictDescription(subject: String) -> String {
        let fields = conflictingFieldNames.joined(separator: ", ")
        return """
            These fields changed elsewhere while you were editing: \(fields). \
            An agent may have updated this \(subject.lowercased()) over MCP, or \
            the change may have synced from another device.

            Keep My Changes overwrites them. Use Updated Values loads the new \
            values into the form so you can review them. Your edits to other \
            fields are kept either way.
            """
    }
}

/// Asks the user how to resolve fields that both they and an external writer
/// changed while an editor was open.
///
/// Presented *instead of* saving: the editor has no basis for preferring one
/// version over the other, so neither is discarded without an explicit choice.
/// Shared by the task, project, and milestone editors so a user never meets two
/// different answers to the same question (T-1798, T-1817).
struct EditConflictAlert<Snapshot: EditSnapshot>: ViewModifier {
    let subject: String
    @Binding var conflict: EditMerge<Snapshot>?
    let keepMine: (EditMerge<Snapshot>) -> Void
    let useTheirs: (EditMerge<Snapshot>) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "\(subject) Changed Elsewhere",
            isPresented: Binding(
                get: { conflict != nil },
                set: { if !$0 { conflict = nil } }
            ),
            presenting: conflict
        ) { merge in
            Button("Keep My Changes", role: .destructive) { keepMine(merge) }
            Button("Use Updated Values", role: .cancel) { useTheirs(merge) }
        } message: { merge in
            Text(merge.conflictDescription(subject: subject))
        }
    }
}

/// Presents a conflict immediately, or after one yield when replacing the alert
/// currently being dismissed by SwiftUI.
@MainActor
func presentEditConflict<Snapshot: EditSnapshot>(
    _ merge: EditMerge<Snapshot>,
    in conflict: Binding<EditMerge<Snapshot>?>,
    replacingShownAlert: Bool
) {
    guard replacingShownAlert else {
        conflict.wrappedValue = merge
        return
    }

    conflict.wrappedValue = nil
    Task { @MainActor in
        await Task.yield()
        conflict.wrappedValue = merge
    }
}

extension View {
    func editConflictAlert<Snapshot: EditSnapshot>(
        subject: String,
        conflict: Binding<EditMerge<Snapshot>?>,
        keepMine: @escaping (EditMerge<Snapshot>) -> Void,
        useTheirs: @escaping (EditMerge<Snapshot>) -> Void
    ) -> some View {
        modifier(
            EditConflictAlert(
                subject: subject,
                conflict: conflict,
                keepMine: keepMine,
                useTheirs: useTheirs
            )
        )
    }
}
