import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var projects: [Project]
    @Environment(ProjectService.self) private var projectService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("syncEnabled") private var syncEnabled = true
    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @State private var showCreateProject = false

    #if os(macOS)
    @Environment(MCPSettings.self) private var mcpSettings
    @Environment(MCPServer.self) private var mcpServer
    #endif

    var body: some View {
        List {
            appearanceSection
            #if os(macOS)
            mcpSection
            #endif
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

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
        }
    }

    #if os(macOS)
    private var mcpSection: some View {
        @Bindable var settings = mcpSettings
        return Section("MCP Server") {
            Toggle("Enable MCP Server", isOn: $settings.isEnabled)
                .onChange(of: mcpSettings.isEnabled) { _, enabled in
                    if enabled {
                        mcpServer.start(port: mcpSettings.port)
                    } else {
                        mcpServer.stop()
                    }
                }

            if mcpSettings.isEnabled {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $settings.port, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Status") {
                    Text(mcpServer.isRunning ? "Running" : "Stopped")
                        .foregroundStyle(mcpServer.isRunning ? .green : .secondary)
                }

                LabeledContent("Setup Command") {
                    let command = "claude mcp add transit --transport http http://localhost:\(mcpSettings.port)/mcp"
                    Text(command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    #endif

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
