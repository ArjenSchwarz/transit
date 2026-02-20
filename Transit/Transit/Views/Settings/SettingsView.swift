import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: \Project.name) private var projects: [Project]
    @Environment(ProjectService.self) private var projectService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("syncEnabled") private var syncEnabled = true
    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @AppStorage("userDisplayName") private var userDisplayName = ""
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedTheme: ResolvedTheme {
        (AppTheme(rawValue: appTheme) ?? .followSystem).resolved(with: colorScheme)
    }
    @State private var showCreateProject = false

    #if os(macOS)
    @Environment(MCPSettings.self) private var mcpSettings
    @Environment(MCPServer.self) private var mcpServer
    #endif

    var body: some View {
        #if os(macOS)
        macOSSettings
        #else
        iOSSettings
        #endif
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSSettings: some View {
        List {
            iOSAppearanceSection
            iOSProjectsSection
            iOSGeneralSection
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar { settingsToolbar }
        .sheet(isPresented: $showCreateProject) {
            NavigationStack {
                ProjectEditView(project: nil)
            }
        }
    }

    private var iOSAppearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appTheme) {
                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
        }
    }

    private var iOSProjectsSection: some View {
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

    private var iOSGeneralSection: some View {
        Section("General") {
            TextField("Your Name", text: $userDisplayName)
            LabeledContent("About Transit", value: appVersion)
            Toggle("iCloud Sync", isOn: $syncEnabled)
        }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private static let labelWidth: CGFloat = 120

    private var macOSSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                macOSAppearanceSection
                macOSMCPSection
                macOSProjectsSection
                macOSGeneralSection
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(true)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { settingsToolbar }
        .sheet(isPresented: $showCreateProject) {
            NavigationStack {
                ProjectEditView(project: nil)
            }
        }
    }

    private var macOSAppearanceSection: some View {
        LiquidGlassSection(title: "Appearance") {
            Grid(
                alignment: .leadingFirstTextBaseline,
                horizontalSpacing: 16,
                verticalSpacing: 14
            ) {
                FormRow("Theme", labelWidth: Self.labelWidth) {
                    Picker("", selection: $appTheme) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }

    private var macOSMCPSection: some View {
        @Bindable var settings = mcpSettings
        return LiquidGlassSection(title: "MCP Server") {
            Grid(
                alignment: .leadingFirstTextBaseline,
                horizontalSpacing: 16,
                verticalSpacing: 14
            ) {
                FormRow("Enabled", labelWidth: Self.labelWidth) {
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                        .onChange(of: mcpSettings.isEnabled) { _, enabled in
                            if enabled {
                                mcpServer.start(port: mcpSettings.port)
                            } else {
                                mcpServer.stop()
                            }
                        }
                }

                if mcpSettings.isEnabled {
                    FormRow("Port", labelWidth: Self.labelWidth) {
                        TextField("", value: $settings.port, format: .number)
                            .frame(width: 80)
                            .onSubmit {
                                guard mcpServer.isRunning else { return }
                                mcpServer.stop()
                                mcpServer.start(port: mcpSettings.port)
                            }
                    }

                    FormRow("Status", labelWidth: Self.labelWidth) {
                        Text(mcpServer.isRunning ? "Running" : "Stopped")
                            .foregroundStyle(mcpServer.isRunning ? .green : .secondary)
                    }

                    FormRow("Setup", labelWidth: Self.labelWidth) {
                        let command =
                            "claude mcp add transit --transport http http://localhost:\(mcpSettings.port)/mcp"
                        Text(command)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var macOSProjectsSection: some View {
        LiquidGlassSection(title: "Projects") {
            VStack(alignment: .leading, spacing: 0) {
                if projects.isEmpty {
                    Text("Create your first project to get started.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(projects) { project in
                        NavigationLink(value: NavigationDestination.projectEdit(project)) {
                            projectRow(project)
                        }
                        .buttonStyle(.plain)
                        if project.id != projects.last?.id {
                            Divider()
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                Button {
                    showCreateProject = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
    }

    private var macOSGeneralSection: some View {
        LiquidGlassSection(title: "General") {
            Grid(
                alignment: .leadingFirstTextBaseline,
                horizontalSpacing: 16,
                verticalSpacing: 14
            ) {
                FormRow("Your Name", labelWidth: Self.labelWidth) {
                    TextField("", text: $userDisplayName)
                        .frame(maxWidth: 200)
                }

                FormRow("Version", labelWidth: Self.labelWidth) {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                FormRow("iCloud Sync", labelWidth: Self.labelWidth) {
                    Toggle("", isOn: $syncEnabled)
                        .labelsHidden()
                }
            }
        }
    }
    #endif

}

// MARK: - Shared Helpers

extension SettingsView {

    @ToolbarContentBuilder
    fileprivate var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
        }
    }

    fileprivate func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            projectSwatch(project)
            Text(project.name)
            Spacer()
            Text("\(projectService.activeTaskCount(for: project))")
                .foregroundStyle(.secondary)
        }
    }

    fileprivate func projectSwatch(_ project: Project) -> some View {
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

    fileprivate var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
