import SwiftUI

struct ProjectFilterMenu: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showPopover = false

    var selectionCount: Int {
        selectedProjectIDs.count
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            filterLabel
        }
        .accessibilityIdentifier("dashboard.filter.projects")
        .accessibilityLabel(accessibilityLabelText)
        #if os(macOS)
        .popover(isPresented: $showPopover) {
            List {
                Section {
                    toggleContent
                }
                clearSection
            }
            .frame(minWidth: 220, minHeight: 200)
        }
        #else
        .sheet(isPresented: $showPopover) {
            NavigationStack {
                List {
                    Section {
                        toggleContent
                    }
                    clearSection
                }
                .navigationTitle("Projects")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showPopover = false }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        #endif
    }

    func toggleBinding(for projectID: UUID) -> Binding<Bool> {
        $selectedProjectIDs.contains(projectID)
    }

    func clearSelection() {
        selectedProjectIDs.removeAll()
    }

    @ViewBuilder
    private var toggleContent: some View {
        ForEach(projects) { project in
            Button {
                if selectedProjectIDs.contains(project.id) {
                    selectedProjectIDs.remove(project.id)
                } else {
                    selectedProjectIDs.insert(project.id)
                }
            } label: {
                HStack {
                    Circle()
                        .fill(Color(hex: project.colorHex))
                        .frame(width: 12, height: 12)
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedProjectIDs.contains(project.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !selectedProjectIDs.isEmpty {
            Section {
                Button("Clear", role: .destructive) {
                    clearSelection()
                }
            }
        }
    }

    private var accessibilityLabelText: String {
        if selectionCount == 0 {
            return "Project filter, no projects selected"
        }
        if selectionCount == 1 {
            return "Project filter, 1 project selected"
        }
        return "Project filter, \(selectionCount) projects selected"
    }

    @ViewBuilder
    private var filterLabel: some View {
        if sizeClass == .compact {
            Image(systemName: selectionCount > 0 ? "folder.fill" : "folder")
                .badge(selectionCount)
        } else {
            Label(
                selectionCount > 0 ? "Projects (\(selectionCount))" : "Projects",
                systemImage: selectionCount > 0 ? "folder.fill" : "folder"
            )
        }
    }
}
