import SwiftData
import SwiftUI

struct TaskEditView: View {
    let task: TransitTask
    var dismissAll: () -> Void
    @Environment(TaskService.self) private var taskService
    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.resolvedTheme) private var resolvedTheme
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var name: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedType: TaskType = .feature
    @State private var selectedStatus: TaskStatus = .idea
    @State private var selectedProjectID: UUID?
    @State private var selectedMilestone: Milestone?
    @State private var metadata: [String: String] = [:]
    @State private var selectedDetent: PresentationDetent = .large
    @State private var errorMessage: String?

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var availableMilestones: [Milestone] {
        Self.availableMilestones(
            project: selectedProject,
            selectedMilestone: selectedMilestone,
            milestoneService: milestoneService
        )
    }

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
        .alert("Error", isPresented: $errorMessage.isPresent) {
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
                PlaceholderTextEditor(
                    text: $taskDescription,
                    placeholder: "Description",
                    minHeight: 120
                )
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
            .onChange(of: selectedProjectID) { oldValue, _ in
                guard oldValue != nil else { return }
                selectedMilestone = nil
            }

            Picker("Milestone", selection: $selectedMilestone.milestoneID(from: availableMilestones)) {
                Text("None").tag(nil as UUID?)
                ForEach(availableMilestones) { milestone in
                    Text(milestone.name).tag(milestone.id as UUID?)
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
                            .onChange(of: selectedProjectID) { oldValue, _ in
                                guard oldValue != nil else { return }
                                selectedMilestone = nil
                            }
                        }

                        FormRow("Milestone", labelWidth: Self.labelWidth) {
                            Picker("", selection: $selectedMilestone.milestoneID(from: availableMilestones)) {
                                Text("None").tag(nil as UUID?)
                                ForEach(availableMilestones, id: \.id) { milestone in
                                    Text(milestone.name).tag(milestone.id as UUID?)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        FormRow("Description", labelWidth: Self.labelWidth) {
                            PlaceholderTextEditor(
                                text: $taskDescription,
                                placeholder: "Description",
                                minHeight: 120
                            )
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
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle("Edit Task")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { dismissAll() } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear { loadTask() }
    }
    #endif

}

// MARK: - Data Loading & Actions

extension TaskEditView {

    static func availableMilestones(
        project: Project?,
        selectedMilestone: Milestone?,
        milestoneService: MilestoneService
    ) -> [Milestone] {
        guard let project else { return [] }
        var milestones = milestoneService.milestonesForProject(project, status: .open)

        guard let selectedMilestone, selectedMilestone.project?.id == project.id else {
            return milestones
        }

        if milestones.contains(where: { $0.id == selectedMilestone.id }) == false {
            milestones.append(selectedMilestone)
        }

        return milestones
    }

    fileprivate func loadTask() {
        name = task.name
        taskDescription = task.taskDescription ?? ""
        selectedType = task.type
        selectedStatus = task.status
        selectedProjectID = task.project?.id
        selectedMilestone = task.milestone
        metadata = task.metadata
    }

    fileprivate func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let trimmedDesc = taskDescription.trimmingCharacters(in: .whitespaces)

        do {
            // All mutations use save: false to defer persistence.
            // A single modelContext.save() at the end makes the operation atomic —
            // either everything persists or everything rolls back.

            // Update project if changed — clears milestone via Decision 6
            if let newProjectID = selectedProjectID, task.project?.id != newProjectID,
               let newProject = projects.first(where: { $0.id == newProjectID }) {
                try taskService.changeProject(task: task, to: newProject, save: false)
            }

            // Apply field mutations through TaskService for validation.
            // Uses save: false to defer persistence until the atomic save below.
            try taskService.updateTask(
                task,
                name: trimmedName,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                type: selectedType,
                metadata: metadata,
                save: false
            )

            // Update milestone via service for validation
            try milestoneService.setMilestone(selectedMilestone, on: task, save: false)

            // Status change goes through TaskService for side effects
            if selectedStatus != task.status {
                try taskService.updateStatus(task: task, to: selectedStatus, save: false)
            }

            try modelContext.save()
            dismissAll()
        } catch {
            modelContext.safeRollback()
            errorMessage = "Could not save task. Please try again."
        }
    }
}
