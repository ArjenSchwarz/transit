import SwiftUI

struct MilestoneEditView: View {
    let project: Project
    let milestone: Milestone?
    @Environment(MilestoneService.self) private var milestoneService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var milestoneDescription: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { milestone != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
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
                TextField("Name", text: $name)
                TextField("Description", text: $milestoneDescription, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(isEditing ? "Edit Milestone" : "New Milestone")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { editToolbar }
        .alert("Save Failed", isPresented: $errorMessage.isPresent) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
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
                            TextField("", text: $name)
                        }

                        FormRow("Description", labelWidth: Self.labelWidth) {
                            TextField("", text: $milestoneDescription, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave || isSaving)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(isEditing ? "Edit Milestone" : "New Milestone")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .alert("Save Failed", isPresented: $errorMessage.isPresent) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", systemImage: "checkmark") { save() }
                .disabled(!canSave || isSaving)
        }
    }

    private func loadMilestone() {
        if let milestone {
            name = milestone.name
            milestoneDescription = milestone.milestoneDescription ?? ""
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = milestoneDescription.trimmingCharacters(in: .whitespaces)

        if let milestone {
            do {
                try milestoneService.updateMilestone(
                    milestone,
                    name: trimmedName,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            isSaving = true
            Task {
                defer { isSaving = false }
                do {
                    try await milestoneService.createMilestone(
                        name: trimmedName,
                        description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                        project: project
                    )
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
                dismiss()
            }
            return
        }
        dismiss()
    }
}
