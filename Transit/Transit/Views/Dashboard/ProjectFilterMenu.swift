import SwiftUI

struct ProjectFilterMenu: View {
    let projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>
    @Environment(\.horizontalSizeClass) private var sizeClass

    #if os(macOS)
    @State private var showPopover = false
    #endif

    var selectionCount: Int {
        selectedProjectIDs.count
    }

    var body: some View {
        #if os(macOS)
        Button {
            showPopover.toggle()
        } label: {
            filterLabel
        }
        .accessibilityIdentifier("dashboard.filter.projects")
        .accessibilityLabel(accessibilityLabelText)
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
        Menu {
            Section {
                toggleContent
            }
            .menuActionDismissBehavior(.disabled)

            clearSection
        } label: {
            filterLabel
        }
        .accessibilityIdentifier("dashboard.filter.projects")
        .accessibilityLabel(accessibilityLabelText)
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
            Toggle(isOn: toggleBinding(for: project.id)) {
                Label(project.name, systemImage: "circle.fill")
                    .foregroundStyle(Color(hex: project.colorHex))
            }
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
