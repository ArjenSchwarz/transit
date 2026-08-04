import SwiftUI

struct MilestoneEditView: View {
    let project: Project
    let milestone: Milestone?
    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.resolvedTheme) private var resolvedTheme

    /// The draft, its baseline, and the load-once guard, held as one value so a
    /// second `onAppear` cannot discard in-flight edits.
    @State private var form = MilestoneEditForm()
    @State private var createSaveLifecycle = MilestoneCreateSaveLifecycle()
    @State private var createSaveTask: Task<Void, Never>?
    @State private var errorMessage: String?

    /// Set when a save finds fields that both the user and an external writer
    /// changed. Presence drives the conflict alert.
    @State private var pendingConflict: MilestoneEditMerge?

    private var isEditing: Bool { milestone != nil }

    private var isSaving: Bool {
        createSaveLifecycle.blocksDismissal
    }

    var body: some View {
        formContent
            .alert("Save Failed", isPresented: $errorMessage.isPresent) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .editConflictAlert(
                subject: "Milestone",
                conflict: $pendingConflict,
                keepMine: { saveExisting(consentingTo: $0) },
                useTheirs: { adoptLiveValues(for: $0) }
            )
            .onDisappear { cancelCreateSaveForDisappearance() }
    }

    private var formContent: some View {
        #if os(macOS)
        macOSForm
        #else
        iOSForm
        #endif
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSForm: some View {
        Form {
            Section {
                TextField("Name", text: $form.name)
                TextField("Description", text: $form.description, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(isEditing ? "Edit Milestone" : "New Milestone")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { editToolbar }
        .interactiveDismissDisabled(isSaving)
        .onAppear { loadMilestone() }
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
                            TextField("", text: $form.name)
                        }

                        FormRow("Description", labelWidth: Self.labelWidth) {
                            TextField("", text: $form.description, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                }

            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle(isEditing ? "Edit Milestone" : "New Milestone")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!form.canSave || isSaving)
            }
        }
        .onAppear { loadMilestone() }
    }
    #endif

    // MARK: - Shared

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", systemImage: "checkmark") { save() }
                .disabled(!form.canSave || isSaving)
        }
    }

    /// Copies the milestone into the form and records the save-time baseline.
    /// Runs once per milestone, so a second `onAppear` leaves the draft alone.
    private func loadMilestone() {
        guard let milestone else { return }
        form.load(from: milestone)
    }

    private func save() {
        guard form.canSave, !isSaving else { return }
        if milestone == nil {
            createMilestone()
        } else {
            saveExisting()
        }
    }

    /// Persists the user's edits to an existing milestone. Consent, when
    /// present, applies only to the exact conflict field values shown.
    private func saveExisting(consentingTo shownConflict: MilestoneEditMerge? = nil) {
        guard let milestone, let merge = form.merge(against: milestone) else { return }

        // Nothing to write. Saving anyway is exactly how the stale form used to
        // revert other writers' changes.
        guard merge.hasChanges else {
            dismiss()
            return
        }

        if merge.hasConflicts {
            guard let shownConflict, merge.hasSameConflictSnapshot(as: shownConflict) else {
                presentEditConflict(merge, in: $pendingConflict, replacingShownAlert: shownConflict != nil)
                return
            }
        }

        pendingConflict = nil
        do {
            let applier = MilestoneEditApplier(milestoneService: milestoneService)
            try applier.apply(merge, edited: merge.edited, to: milestone)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        dismiss()
    }

    private func createMilestone() {
        guard createSaveLifecycle.beginSave() else { return }
        let edited = form.edited

        let saveTask = Task { @MainActor in
            do {
                try await milestoneService.createMilestone(
                    name: edited.name,
                    description: edited.description.isEmpty ? nil : edited.description,
                    project: project
                )
                try Task.checkCancellation()

                // Record success before dismissal so the resulting `onDisappear`
                // cannot cancel an operation that has already persisted.
                guard createSaveLifecycle.completeSave() else { return }
                createSaveTask = nil
                dismiss()
            } catch is CancellationError {
                finishCancelledCreate()
            } catch {
                if Task.isCancelled {
                    finishCancelledCreate()
                } else {
                    createSaveLifecycle.completeFailure()
                    createSaveTask = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
        createSaveTask = saveTask
    }

    private func cancelCreateSaveForDisappearance() {
        guard createSaveLifecycle.cancelForDisappearance() else { return }
        createSaveTask?.cancel()
    }

    private func finishCancelledCreate() {
        createSaveLifecycle.completeCancellation()
        createSaveTask = nil
    }

    /// Recomputes before using external values. Changed conflict fields or
    /// values cause a new alert; otherwise the form performs a complete safe
    /// rebase and remains open for review.
    private func adoptLiveValues(for shownConflict: MilestoneEditMerge) {
        guard let milestone, let merge = form.merge(against: milestone) else { return }
        guard !merge.hasConflicts || merge.hasSameConflictSnapshot(as: shownConflict) else {
            presentEditConflict(merge, in: $pendingConflict, replacingShownAlert: true)
            return
        }

        form.adoptLiveValues(for: merge)
        pendingConflict = nil
    }
}
