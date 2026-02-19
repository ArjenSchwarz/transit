import SwiftData
import SwiftUI

struct TaskEditView: View {
    let task: TransitTask
    var dismissAll: () -> Void
    @Environment(TaskService.self) private var taskService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var name: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedType: TaskType = .feature
    @State private var selectedStatus: TaskStatus = .idea
    @State private var selectedProjectID: UUID?
    @State private var metadata: [String: String] = [:]
    @State private var selectedDetent: PresentationDetent = .large
    @State private var errorMessage: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedProjectID != nil
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            macOSForm
            #else
            iOSForm
            #endif
        }
        .alert("Save Failed", isPresented: $errorMessage.isPresent) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSForm: some View {
        Form {
            iOSFieldsSection

            Section {
                ZStack(alignment: .topLeading) {
                    if taskDescription.isEmpty {
                        Text("Description")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $taskDescription)
                        .frame(minHeight: 120, maxHeight: .infinity)
                }
            }

            iOSStatusSection
            MetadataSection(metadata: $metadata, isEditing: true)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear { loadTask() }
    }

    private var iOSFieldsSection: some View {
        Section {
            TextField("Name", text: $name)

            Picker("Type", selection: $selectedType) {
                ForEach(TaskType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            Picker("Project", selection: $selectedProjectID) {
                ForEach(projects) { project in
                    HStack {
                        ProjectColorDot(color: Color(hex: project.colorHex))
                        Text(project.name)
                    }
                    .tag(Optional(project.id))
                }
            }
        }
    }

    private var iOSStatusSection: some View {
        Section {
            Picker("Status", selection: $selectedStatus) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
        }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private static let labelWidth: CGFloat = 90

    private var macOSForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LiquidGlassSection(title: "Details") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
                        FormRow("Name", labelWidth: Self.labelWidth) {
                            TextField("", text: $name)
                        }

                        FormRow("Description", labelWidth: Self.labelWidth) {
                            ZStack(alignment: .topLeading) {
                                if taskDescription.isEmpty {
                                    Text("Description")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }
                                TextEditor(text: $taskDescription)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                            }
                            .padding(4)
                            .background(Color(.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                        }

                        FormRow("Type", labelWidth: Self.labelWidth) {
                            Picker("", selection: $selectedType) {
                                ForEach(TaskType.allCases, id: \.self) { type in
                                    Text(type.rawValue.capitalized).tag(type)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        FormRow("Project", labelWidth: Self.labelWidth) {
                            Picker("", selection: $selectedProjectID) {
                                ForEach(projects) { project in
                                    HStack {
                                        ProjectColorDot(color: Color(hex: project.colorHex))
                                        Text(project.name)
                                    }
                                    .tag(Optional(project.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }
                }

                LiquidGlassSection(title: "Status") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
                        FormRow("Status", labelWidth: Self.labelWidth) {
                            Picker("", selection: $selectedStatus) {
                                ForEach(TaskStatus.allCases, id: \.self) { status in
                                    Text(status.displayName).tag(status)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }
                }

                LiquidGlassSection(title: "Metadata") {
                    MetadataSection(metadata: $metadata, isEditing: true)
                }

                HStack {
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Edit Task")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .onAppear { loadTask() }
    }
    #endif

    // MARK: - Data Loading

    private func loadTask() {
        name = task.name
        taskDescription = task.taskDescription ?? ""
        selectedType = task.type
        selectedStatus = task.status
        selectedProjectID = task.project?.id
        metadata = task.metadata
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        task.name = trimmedName

        let trimmedDesc = taskDescription.trimmingCharacters(in: .whitespaces)
        task.taskDescription = trimmedDesc.isEmpty ? nil : trimmedDesc

        task.type = selectedType
        task.metadata = metadata

        // Update project if changed
        if let newProjectID = selectedProjectID, task.project?.id != newProjectID {
            task.project = projects.first { $0.id == newProjectID }
        }

        do {
            // Status change goes through TaskService for side effects (which saves internally)
            if selectedStatus != task.status {
                try taskService.updateStatus(task: task, to: selectedStatus)
            } else {
                try modelContext.save()
            }
            dismissAll()
        } catch {
            modelContext.rollback()
            errorMessage = "Could not save task. Please try again."
        }
    }
}
