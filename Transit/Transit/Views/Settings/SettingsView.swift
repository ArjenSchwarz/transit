import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var projects: [Project]
    @Environment(ProjectService.self) private var projectService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("syncEnabled") private var syncEnabled = true
    @State private var showCreateProject = false

    var body: some View {
        List {
            projectsSection
            generalSection
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .sheet(isPresented: $showCreateProject) {
            NavigationStack {
                ProjectEditView(project: nil)
            }
        }
    }

    // MARK: - Sections

    private var projectsSection: some View {
        Section {
            if projects.isEmpty {
                Text("Create your first project to get started.")
                    .foregroundStyle(.secondary)
            }
            ForEach(projects) { project in
                NavigationLink(value: NavigationDestination.projectEdit(project)) {
                    projectRow(project)
                }
            }
        } header: {
            HStack {
                Text("Projects")
                Spacer()
                Button {
                    showCreateProject = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            projectSwatch(project)
            Text(project.name)
            Spacer()
            Text("\(projectService.activeTaskCount(for: project))")
                .foregroundStyle(.secondary)
        }
    }

    private func projectSwatch(_ project: Project) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hex: project.colorHex))
            .frame(width: 28, height: 28)
            .overlay {
                Text(String(project.name.prefix(1)).uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
    }

    private var generalSection: some View {
        Section("General") {
            LabeledContent("About Transit", value: appVersion)
            Toggle("iCloud Sync", isOn: $syncEnabled)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
