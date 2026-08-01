import SwiftData
import SwiftUI

struct ProjectEditView: View {
    let project: Project?
    @Environment(ProjectService.self) private var projectService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.resolvedTheme) private var resolvedTheme

    /// The draft, its baseline, and the load-once guard, held as one value so a
    /// second `onAppear` — returning from the pushed milestone editor — cannot
    /// discard in-flight edits (T-1880).
    @State private var form = ProjectEditForm(colorHex: Color.blue.hexString)
    @State private var errorMessage: String?

    /// Set when a save finds fields that both the user and an external writer
    /// changed. Presence drives the conflict alert.
    @State private var pendingConflict: ProjectEditMerge?

    private var isEditing: Bool { project != nil }

    var body: some View {
        formContent
            .alert("Save Failed", isPresented: $errorMessage.isPresent) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .editConflictAlert(
                subject: "Project",
                conflict: $pendingConflict,
                keepMine: { saveExisting(consentingTo: $0) },
                useTheirs: { adoptLiveValues(for: $0) }
            )
    }

    private var formContent: some View {
        #if os(macOS)
        macOSForm
        #else
        iOSForm
        #endif
    }

    /// `ColorPicker` speaks `Color`; the draft stores the hex string that is
    /// actually persisted, so the merge compares stored values rather than
    /// colour-space components.
    fileprivate var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: form.colorHex) },
            set: { form.colorHex = $0.hexString }
        )
    }
}

// MARK: - iOS Layout

#if os(iOS)
extension ProjectEditView {
    fileprivate var iOSForm: some View {
        Form {
            Section {
                TextField("Name", text: $form.name)
                TextField("Description", text: $form.description, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Git Repo URL", text: $form.gitRepo)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            }

            if let project {
                MilestoneListSection(project: project)
            }
        }
        .navigationTitle(isEditing ? "Edit Project" : "New Project")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { editToolbar }
        .onAppear { loadProject() }
    }
}
#endif

// MARK: - macOS Layout

#if os(macOS)
extension ProjectEditView {
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
                            TextField("", text: $form.name)
                        }

                        FormRow("Description", labelWidth: Self.labelWidth) {
                            TextField("", text: $form.description, axis: .vertical)
                                .lineLimit(3...6)
                        }

                        FormRow("Git Repo", labelWidth: Self.labelWidth) {
                            TextField("", text: $form.gitRepo)
                                .autocorrectionDisabled()
                        }

                        FormRow("Color", labelWidth: Self.labelWidth) {
                            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                                .labelsHidden()
                                .fixedSize()
                        }
                    }
                }

                if let project {
                    MilestoneListSection(project: project)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle(isEditing ? "Edit Project" : "New Project")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!form.canSave)
            }
        }
        .onAppear { loadProject() }
    }
}
#endif

// MARK: - Data Loading & Actions

extension ProjectEditView {

    @ToolbarContentBuilder
    fileprivate var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", systemImage: "checkmark") { save() }
                .disabled(!form.canSave)
        }
    }

    /// Copies the project into the form and records the save-time baseline.
    ///
    /// `ProjectEditForm.load` runs once per project, so the `onAppear` fired by
    /// popping the milestone editor back off the stack leaves the draft alone
    /// (T-1880).
    fileprivate func loadProject() {
        guard let project else { return }
        form.load(from: project)
    }

    fileprivate func save() {
        guard form.canSave else { return }
        if project == nil {
            createProject()
        } else {
            saveExisting()
        }
    }

    /// Persists the user's edits to an existing project. Consent, when present,
    /// applies only to the exact conflict field values shown by that alert.
    fileprivate func saveExisting(consentingTo shownConflict: ProjectEditMerge? = nil) {
        guard let project, let merge = form.merge(against: project) else { return }

        // Nothing to write. Saving anyway is exactly how the stale form used to
        // revert other writers' changes.
        guard merge.hasChanges else {
            dismiss()
            return
        }

        if merge.hasConflicts {
            guard let shownConflict, merge.hasSameConflictSnapshot(as: shownConflict) else {
                presentConflict(merge, replacingShownAlert: shownConflict != nil)
                return
            }
        }

        pendingConflict = nil
        do {
            let applier = ProjectEditApplier(projectService: projectService)
            try applier.apply(merge, edited: merge.edited, to: project)
        } catch ProjectMutationError.invalidName {
            errorMessage = "Project name cannot be empty."
            return
        } catch ProjectMutationError.duplicateName(let conflictingName) {
            errorMessage = "A project named \"\(conflictingName)\" already exists."
            return
        } catch {
            // updateProject rolls back on save failure, reverting the model to its
            // last-persisted values. The form's draft is unaffected, so the editor
            // keeps the user's in-progress edits.
            errorMessage = "Could not save project. Please try again."
            return
        }
        dismiss()
    }

    fileprivate func createProject() {
        let edited = form.edited
        do {
            try projectService.createProject(
                name: edited.name,
                description: edited.description,
                gitRepo: edited.gitRepo.isEmpty ? nil : edited.gitRepo,
                colorHex: edited.colorHex
            )
        } catch ProjectMutationError.invalidName {
            errorMessage = "Project name cannot be empty."
            return
        } catch ProjectMutationError.duplicateName(let conflictingName) {
            errorMessage = "A project named \"\(conflictingName)\" already exists."
            return
        } catch {
            errorMessage = "Failed to create project."
            return
        }
        dismiss()
    }

    /// Re-presents a changed conflict after the current alert has dismissed.
    fileprivate func presentConflict(_ merge: ProjectEditMerge, replacingShownAlert: Bool) {
        guard replacingShownAlert else {
            pendingConflict = merge
            return
        }

        pendingConflict = nil
        Task { @MainActor in
            await Task.yield()
            pendingConflict = merge
        }
    }

    /// Recomputes before using external values. Changed conflict fields or
    /// values cause a new alert; otherwise the form performs a complete safe
    /// rebase and remains open for review.
    fileprivate func adoptLiveValues(for shownConflict: ProjectEditMerge) {
        guard let project, let merge = form.merge(against: project) else { return }
        guard !merge.hasConflicts || merge.hasSameConflictSnapshot(as: shownConflict) else {
            presentConflict(merge, replacingShownAlert: true)
            return
        }

        form.adoptLiveValues(for: merge)
        pendingConflict = nil
    }
}
