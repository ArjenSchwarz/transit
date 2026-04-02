import SwiftData
import SwiftUI

struct AddTaskSheet: View {
    @Environment(TaskService.self) private var taskService
    @Environment(ProjectService.self) private var projectService
    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.resolvedTheme) private var resolvedTheme
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var name = ""
    @State private var taskDescription = ""
    @State private var selectedType: TaskType = .feature
    @State private var selectedProjectID: UUID?
    @State private var selectedMilestone: Milestone?
    @State private var selectedDetent: PresentationDetent = .large
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var openMilestones: [Milestone] {
        guard let project = selectedProject else { return [] }
        return milestoneService.milestonesForProject(project, status: .open)
    }

    private var selectedMilestoneID: Binding<UUID?> {
        Binding(
            get: { selectedMilestone?.id },
            set: { newID in
                selectedMilestone = openMilestones.first { $0.id == newID }
            }
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedProject != nil
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
            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
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

                Picker("Milestone", selection: selectedMilestoneID) {
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
                            Picker("", selection: selectedMilestoneID) {
                                Text("None").tag(nil as UUID?)
                                ForEach(openMilestones) { milestone in
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

    // MARK: - Actions

    private func save() async {
        guard let project = selectedProject else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let description = taskDescription.trimmingCharacters(in: .whitespaces)
        let type = selectedType
        let projectID = project.id

        isSaving = true
        defer { isSaving = false }

        do {
            let task = try await taskService.createTask(
                name: trimmedName,
                description: description.isEmpty ? nil : description,
                type: type,
                projectID: projectID
            )
            if let milestone = selectedMilestone {
                try milestoneService.setMilestone(milestone, on: task)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
