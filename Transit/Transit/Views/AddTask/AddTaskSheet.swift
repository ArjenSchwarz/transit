import SwiftData
import SwiftUI

struct AddTaskSheet: View {
    @Environment(TaskService.self) private var taskService
    @Environment(ProjectService.self) private var projectService
    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .presentationDetents([.medium, .large], selection: $selectedDetent)
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

                Picker("Milestone", selection: $selectedMilestone) {
                    Text("None").tag(nil as Milestone?)
                    ForEach(openMilestones) { milestone in
                        Text(milestone.name).tag(milestone as Milestone?)
                    }
                }

                TextField("Name", text: $name)
            }

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

            Section {
                Picker("Type", selection: $selectedType) {
                    ForEach(TaskType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
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
                LiquidGlassSection(title: "Task") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
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
                            Picker("", selection: $selectedMilestone) {
                                Text("None").tag(nil as Milestone?)
                                ForEach(openMilestones) { milestone in
                                    Text(milestone.name).tag(milestone as Milestone?)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

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
                    }
                }

                LiquidGlassSection(title: "Type") {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 14
                    ) {
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
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
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
