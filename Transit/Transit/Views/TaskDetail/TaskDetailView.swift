import SwiftUI

struct TaskDetailView: View {
    let task: TransitTask
    var dismissAll: () -> Void
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false

    var body: some View {
        NavigationStack {
            #if os(macOS)
            macOSDetail
            #else
            iOSDetail
            #endif
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSDetail: some View {
        Form {
            iOSDetailSection
            iOSDescriptionSection
            MetadataSection(metadata: .constant(task.metadata), isEditing: false)
            CommentsSection(task: task)
            iOSActionSection
        }
        .navigationTitle(task.displayID.formatted)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .sheet(isPresented: $showEdit) {
            TaskEditView(task: task, dismissAll: dismissAll)
        }
    }

    private var iOSDetailSection: some View {
        Section {
            LabeledContent("Name", value: task.name)
            LabeledContent("Type") { TypeBadge(type: task.type) }
            LabeledContent("Status", value: task.status.displayName)
            if let project = task.project {
                LabeledContent("Project") {
                    HStack {
                        ProjectColorDot(color: Color(hex: project.colorHex))
                        Text(project.name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var iOSDescriptionSection: some View {
        if let description = task.taskDescription, !description.isEmpty {
            Section("Description") {
                Text(description)
            }
        }
    }

    private var iOSActionSection: some View {
        Section {
            actionButtons
        }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private static let labelWidth: CGFloat = 90

    private var macOSDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiquidGlassSection(title: "Details") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
                        FormRow("Name", labelWidth: Self.labelWidth) {
                            Text(task.name)
                        }

                        FormRow("Type", labelWidth: Self.labelWidth) {
                            TypeBadge(type: task.type)
                        }

                        FormRow("Status", labelWidth: Self.labelWidth) {
                            Text(task.status.displayName)
                        }

                        if let project = task.project {
                            FormRow("Project", labelWidth: Self.labelWidth) {
                                HStack {
                                    ProjectColorDot(color: Color(hex: project.colorHex))
                                    Text(project.name)
                                }
                            }
                        }
                    }
                }

                if let description = task.taskDescription, !description.isEmpty {
                    LiquidGlassSection(title: "Description") {
                        Text(description)
                    }
                }

                LiquidGlassSection(title: "Metadata") {
                    MetadataSection(metadata: .constant(task.metadata), isEditing: false)
                }

                CommentsSection(task: task)

                LiquidGlassSection(title: "Actions") {
                    actionButtons
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(task.displayID.formatted)
        .toolbar { detailToolbar }
        .sheet(isPresented: $showEdit) {
            TaskEditView(task: task, dismissAll: dismissAll)
        }
    }
    #endif

    // MARK: - Shared

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            HStack(spacing: 12) {
                ShareLink(item: task.shareText, subject: Text(task.name)) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if task.status == .abandoned {
            Button("Restore to Idea") {
                try? taskService.restore(task: task)
                dismiss()
            }
        } else {
            // Abandon from any status including Done [req 4.5]
            Button("Abandon", role: .destructive) {
                try? taskService.abandon(task: task)
                dismiss()
            }
        }
    }
}
