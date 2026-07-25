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
    @State private var selectedPriority: TaskPriority = .medium
    @State private var selectedStatus: TaskStatus = .idea
    @State private var selectedProjectID: UUID?
    @State private var selectedMilestone: Milestone?
    @State private var metadata: [String: String] = [:]
    @State private var selectedDetent: PresentationDetent = .large
    @State private var errorMessage: String?

    /// The task's values when the editor loaded. Diffing the form against this
    /// baseline is what tells "the user set this" apart from "this is merely
    /// what was loaded", so a save writes only the fields the user touched
    /// (T-1798). `nil` until `loadTask()` runs.
    @State private var originalSnapshot: TaskEditSnapshot?

    /// Set when a save finds fields that both the user and an external writer
    /// changed. Presence drives the conflict alert.
    @State private var pendingConflict: TaskEditMerge?

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
        !name.trimmedForFormInput().isEmpty && selectedProjectID != nil
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
        .taskEditConflictAlert(
            conflict: $pendingConflict,
            keepMine: { save(overwritingConflicts: true) },
            useTheirs: { adoptLiveValues(for: $0) }
        )
    }
}

// MARK: - iOS Layout

#if os(iOS)
extension TaskEditView {
    fileprivate var iOSForm: some View {
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

    fileprivate var iOSFieldsSection: some View {
        Section {
            TextField("Name", text: $name)

            Picker("Type", selection: $selectedType) {
                ForEach(TaskType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            Picker("Priority", selection: $selectedPriority) {
                ForEach(TaskPriority.displayOrder, id: \.self) { priority in
                    Text(priority.rawValue.capitalized).tag(priority)
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
            .onChange(of: selectedProjectID) { oldValue, newValue in
                guard oldValue != nil, newValue != task.project?.id else { return }
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

    fileprivate var iOSStatusSection: some View {
        Section {
            Picker("Status", selection: $selectedStatus) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
        }
    }
}
#endif

// MARK: - macOS Layout

#if os(macOS)
extension TaskEditView {
    fileprivate static let labelWidth: CGFloat = 90

    fileprivate var macOSForm: some View {
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

                        FormRow("Priority", labelWidth: Self.labelWidth) {
                            Picker("", selection: $selectedPriority) {
                                ForEach(TaskPriority.displayOrder, id: \.self) { priority in
                                    Text(priority.rawValue.capitalized).tag(priority)
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
                            .onChange(of: selectedProjectID) { oldValue, newValue in
                                guard oldValue != nil, newValue != task.project?.id else { return }
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
}
#endif

// MARK: - Data Loading & Actions

extension TaskEditView {

    /// Copies the task into the form and records the baseline the save-time
    /// merge diffs against.
    ///
    /// Runs once. A second `onAppear` — returning from a pushed screen, for
    /// instance — must not discard in-flight edits or reset the baseline, which
    /// would make every field look untouched again.
    fileprivate func loadTask() {
        guard originalSnapshot == nil else { return }

        name = task.name
        taskDescription = task.taskDescription ?? ""
        selectedType = task.type
        selectedPriority = task.priority
        selectedStatus = task.status
        selectedProjectID = task.project?.id
        selectedMilestone = task.milestone
        metadata = task.metadata
        originalSnapshot = TaskEditSnapshot(task: task)
    }

    fileprivate func editedSnapshot() -> TaskEditSnapshot {
        TaskEditSnapshot(
            name: name,
            description: taskDescription,
            type: selectedType,
            priority: selectedPriority,
            status: selectedStatus,
            projectID: selectedProjectID,
            milestoneID: selectedMilestone?.id,
            metadata: metadata
        )
    }

    /// Persists the user's edits.
    ///
    /// Only fields the user actually changed are written, so a concurrent MCP or
    /// CloudKit write to a *different* field survives (T-1798). When both sides
    /// changed the *same* field the save stops and asks;
    /// `overwritingConflicts` carries the user's answer back in.
    fileprivate func save(overwritingConflicts: Bool = false) {
        guard let originalSnapshot else { return }

        let edited = editedSnapshot()
        guard !edited.name.isEmpty else { return }

        let merge = TaskEditMerge(
            original: originalSnapshot,
            edited: edited,
            live: TaskEditSnapshot(task: task)
        )

        // Nothing to write. Saving anyway is exactly how the stale form used to
        // revert other writers' changes.
        guard merge.hasChanges else {
            dismissAll()
            return
        }

        if merge.hasConflicts, !overwritingConflicts {
            pendingConflict = merge
            return
        }

        do {
            // Every mutation defers persistence. The single save inside
            // `saveOrRollback` makes the edit atomic — all of it lands or none
            // of it does.
            try modelContext.saveOrRollback {
                let applier = TaskEditApplier(taskService: taskService, milestoneService: milestoneService)
                try applier.apply(
                    merge,
                    edited: edited,
                    to: task,
                    project: selectedProject,
                    milestone: selectedMilestone
                )
            }
            dismissAll()
        } catch {
            errorMessage = "Could not save task. Please try again."
        }
    }

    /// Drops the user's edits to the conflicting fields in favour of the values
    /// now on the task, and re-baselines so untouched fields stay untouched and
    /// the user's other edits stay pending.
    ///
    /// The editor deliberately stays open and nothing is saved: the point is to
    /// show the user what the other writer did before they commit to anything.
    fileprivate func adoptLiveValues(for merge: TaskEditMerge) {
        for field in merge.conflictingFields {
            switch field {
            case .name: name = task.name
            case .description: taskDescription = task.taskDescription ?? ""
            case .type: selectedType = task.type
            case .priority: selectedPriority = task.priority
            case .status: selectedStatus = task.status
            case .project: selectedProjectID = task.project?.id
            case .milestone: selectedMilestone = task.milestone
            case .metadata: metadata = task.metadata
            }
        }

        originalSnapshot = TaskEditSnapshot(task: task)
        pendingConflict = nil
    }
}
