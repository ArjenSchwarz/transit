import SwiftData
import SwiftUI

struct AddTaskSheet: View {
    // Several members below are `internal` (not `private`) so the
    // `AddTaskSheet+Save.swift` extension can reach them. The split exists to
    // keep this type under SwiftLint's type-body-length limit; the access
    // widening is incidental, so do not re-tighten these to `private`.
    @Environment(TaskService.self) var taskService
    @Environment(ProjectService.self) private var projectService
    @Environment(MilestoneService.self) var milestoneService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.resolvedTheme) private var resolvedTheme
    @Query(sort: \Project.name) private var projects: [Project]

    @State var name = ""
    @State var taskDescription = ""
    @State var selectedType: TaskType = .feature
    @State var selectedPriority: TaskPriority = .medium
    @State private var selectedProjectID: UUID?
    @State var selectedMilestone: Milestone?
    @State private var selectedDetent: PresentationDetent = .large
    @State var isSaving = false
    @State var errorMessage: String?

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var openMilestones: [Milestone] {
        guard let project = selectedProject else { return [] }
        return milestoneService.milestonesForProject(project, status: .open)
    }

    private var canSave: Bool {
        !name.trimmedForFormInput().isEmpty && selectedProject != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    EmptyStateView(message: "No projects yet. Create one in Settings.")
                } else {
                    #if os(macOS)
                    macOSForm
                    #else
                    iOSForm
                    #endif
                }
            }
            .navigationTitle("New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(isSaving)
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    #if os(macOS)
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    #else
                    Button("Save", systemImage: "checkmark") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    #endif
                }
            }
        }
        #if os(iOS)
        .interactiveDismissDisabled(isSaving)
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        #endif
        .alert("Save Failed", isPresented: $errorMessage.isPresent) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            #if os(macOS)
            // `Window("New Task", id: "add-task")` is a singleton scene whose
            // view (and `@State`) is reused across opens, so after one save
            // the next open would still show the previous values (T-825).
            // Reset to defaults every time the view appears.
            resetForm()
            #else
            // On iOS the view is freshly constructed by `.sheet(isPresented:)`
            // on each presentation, so we only need to pick a default project.
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
            #endif
        }
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSForm: some View {
        Form {
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
                .onChange(of: selectedProjectID) { _, _ in
                    selectedMilestone = nil
                }

                Picker("Milestone", selection: $selectedMilestone.milestoneID(from: openMilestones)) {
                    Text("None").tag(nil as UUID?)
                    ForEach(openMilestones) { milestone in
                        Text(milestone.name).tag(milestone.id as UUID?)
                    }
                }
            }

            Section {
                PlaceholderTextEditor(
                    text: $taskDescription,
                    placeholder: "Description",
                    minHeight: 120
                )
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
                LiquidGlassSection(title: "Task") {
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
                            .onChange(of: selectedProjectID) { _, _ in
                                selectedMilestone = nil
                            }
                        }

                        FormRow("Milestone", labelWidth: Self.labelWidth) {
                            Picker("", selection: $selectedMilestone.milestoneID(from: openMilestones)) {
                                Text("None").tag(nil as UUID?)
                                ForEach(openMilestones, id: \.id) { milestone in
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
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
    }
    #endif

    // MARK: - Reset

    #if os(macOS)
    /// Resets every form field to its default. Only used on macOS where the
    /// `Window("New Task", …)` scene reuses the same view (and its `@State`)
    /// across opens, so without an explicit reset the form would still show
    /// the previously entered values (T-825).
    private func resetForm() {
        let defaults = AddTaskFormResetLogic.defaults
        name = defaults.name
        taskDescription = defaults.description
        selectedType = defaults.type
        selectedPriority = defaults.priority
        selectedMilestone = defaults.milestone
        selectedProjectID = AddTaskFormResetLogic.defaultProjectID(
            from: projects, current: selectedProjectID
        )
        errorMessage = nil
        isSaving = false
    }
    #endif

}

// MARK: - Form Reset Logic

/// Pure helpers for AddTaskSheet's form reset behaviour. Extracted so the
/// default values and project-fallback rule are exercisable in unit tests
/// without spinning up SwiftUI.
///
/// See T-825: on macOS the `Window("New Task", …)` scene reuses one view
/// instance across opens, so the form must be explicitly reset on appear.
enum AddTaskFormResetLogic {

    struct Defaults {
        let name: String
        let description: String
        let type: TaskType
        let priority: TaskPriority
        let milestone: Milestone?
    }

    static let defaults = Defaults(
        name: "",
        description: "",
        type: .feature,
        priority: .medium,
        milestone: nil
    )

    /// Returns the project ID to select when the form is reset.
    ///
    /// - Keeps the `current` selection when it still maps to a known project,
    ///   so reopening the window after a save doesn't surprise the user by
    ///   jumping back to the first project.
    /// - Falls back to the first project otherwise (no current selection, or
    ///   the previously selected project has been deleted).
    /// - Returns `nil` when there are no projects at all.
    static func defaultProjectID(from projects: [Project], current: UUID?) -> UUID? {
        if let current, projects.contains(where: { $0.id == current }) {
            return current
        }
        return projects.first?.id
    }
}
