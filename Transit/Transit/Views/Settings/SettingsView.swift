import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: \Project.name) private var projects: [Project]
    @Environment(ProjectService.self) private var projectService
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif
    @AppStorage("syncEnabled") private var syncEnabled = true
    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @AppStorage("userDisplayName") private var userDisplayName = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SyncManager.self) private var syncManager

    private var resolvedTheme: ResolvedTheme {
        (AppTheme(rawValue: appTheme) ?? .followSystem).resolved(with: colorScheme)
    }
    @State private var showCreateProject = false

    #if os(macOS)
    @Environment(MCPSettings.self) private var mcpSettings
    @Environment(MCPServer.self) private var mcpServer
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var detailPath = NavigationPath()
    @State private var categoryHistory: [SettingsCategory] = [.general]
    @State private var historyIndex = 0
    @State private var isNavigatingHistory = false
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
            iOSDataMaintenanceSection
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

    private var iOSDataMaintenanceSection: some View {
        Section("Data Maintenance") {
            NavigationLink(value: NavigationDestination.dataMaintenance) {
                Label("Data Maintenance", systemImage: "wrench.and.screwdriver")
            }
            .accessibilityIdentifier("dataMaintenance.row")
        }
    }

    private var iOSGeneralSection: some View {
        Section("General") {
            TextField("Your Name", text: $userDisplayName)
            LabeledContent("About Transit", value: appVersion)
            Toggle("iCloud Sync", isOn: $syncEnabled)
                .onChange(of: syncEnabled) { _, enabled in
                    syncManager.setSyncEnabled(enabled)
                }
            NavigationLink(value: NavigationDestination.acknowledgments) {
                Text("Acknowledgments")
            }
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
        }
    }
    #endif

    // MARK: - Shared Helpers

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: project.colorHex))
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String(project.name.prefix(1)).uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            Text(project.name)
            Spacer()
            Text("\(projectService.activeTaskCount(for: project))")
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - macOS Layout

#if os(macOS)
extension SettingsView {
    fileprivate static var labelWidth: CGFloat { 90 }

    fileprivate var macOSSettings: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.title, systemImage: category.icon)
                        .tag(category)
                }
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $detailPath) {
                settingsDetailContent
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .projectCreate:
                            ProjectEditView(project: nil)
                        case .projectEdit(let project):
                            ProjectEditView(project: project)
                        case .milestoneEdit(let project, let milestone):
                            MilestoneEditView(project: project, milestone: milestone)
                        case .licenseText:
                            LicenseTextView()
                        default:
                            EmptyView()
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedCategory) { _, newValue in
            detailPath = NavigationPath()
            if isNavigatingHistory {
                isNavigatingHistory = false
                return
            }
            guard let newValue else { return }
            categoryHistory = Array(categoryHistory.prefix(historyIndex + 1))
            categoryHistory.append(newValue)
            historyIndex = categoryHistory.count - 1
        }
    }

    private func navigateBack() {
        guard historyIndex > 0 else { return }
        isNavigatingHistory = true
        historyIndex -= 1
        selectedCategory = categoryHistory[historyIndex]
    }

    private func navigateForward() {
        guard historyIndex < categoryHistory.count - 1 else { return }
        isNavigatingHistory = true
        historyIndex += 1
        selectedCategory = categoryHistory[historyIndex]
    }

    fileprivate var settingsDetailContent: some View {
        Group {
            switch selectedCategory {
            case .general:
                settingsDetailWrapper {
                    macOSAppearanceSection
                    macOSGeneralSection
                }
            case .projects:
                settingsDetailWrapper { macOSProjectsSection }
            case .mcpServer:
                settingsDetailWrapper { macOSMCPSection }
            case .dataMaintenance:
                DataMaintenanceView()
            case .acknowledgments:
                AcknowledgmentsView()
            case nil:
                settingsDetailWrapper {
                    macOSAppearanceSection
                    macOSGeneralSection
                }
            }
        }
        .navigationTitle(selectedCategory?.title ?? "General")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 0) {
                    Button { navigateBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(historyIndex <= 0)
                    Button { navigateForward() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(historyIndex >= categoryHistory.count - 1)
                }
            }
        }
    }

    fileprivate func settingsDetailWrapper<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content()
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background { BoardBackground(theme: resolvedTheme) }
    }

    fileprivate var macOSAppearanceSection: some View {
        LiquidGlassSection(title: "Appearance") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
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

    fileprivate var macOSMCPSection: some View {
        @Bindable var settings = mcpSettings
        return LiquidGlassSection {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
                FormRow("Enabled", labelWidth: Self.labelWidth) {
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: mcpSettings.isEnabled) { _, enabled in
                            if enabled {
                                mcpServer.start(port: mcpSettings.port)
                                syncManager.startHeartbeat(context: modelContext)
                            } else {
                                mcpServer.stop()
                                syncManager.stopHeartbeat()
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
                FormRow("Maintenance", labelWidth: Self.labelWidth) {
                    Toggle("Expose maintenance tools", isOn: $settings.maintenanceToolsEnabled)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    fileprivate var macOSProjectsSection: some View {
        LiquidGlassSection {
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
                Divider().padding(.vertical, 4)
                NavigationLink(value: NavigationDestination.projectCreate) {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
    }

    fileprivate var macOSGeneralSection: some View {
        LiquidGlassSection {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
                FormRow("Your Name", labelWidth: Self.labelWidth) {
                    TextField("", text: $userDisplayName)
                }
                FormRow("Version", labelWidth: Self.labelWidth) {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                FormRow("iCloud Sync", labelWidth: Self.labelWidth) {
                    Toggle("", isOn: $syncEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: syncEnabled) { _, enabled in
                            syncManager.setSyncEnabled(enabled)
                        }
                }
            }
        }
    }
}
#endif
