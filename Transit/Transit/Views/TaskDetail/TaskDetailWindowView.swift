#if os(macOS)
import SwiftData
import SwiftUI

/// macOS-only wrapper that resolves a task UUID for use in a `Window` scene.
/// Manages the detail ↔ edit transition within the window.
struct TaskDetailWindowView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    private var task: TransitTask? {
        var descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        if let task {
            if isEditing {
                TaskEditView(task: task, dismissAll: { isEditing = false })
            } else {
                TaskDetailView(task: task, dismissAll: { dismiss() }, onEdit: { isEditing = true })
            }
        } else {
            ContentUnavailableView("Task Not Found", systemImage: "questionmark.circle")
        }
    }
}
#endif
