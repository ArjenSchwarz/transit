import AppIntents
import CloudKit
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif
@main
// App composition retains lifetime-owned services and scene wiring together.
struct TransitApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor private var appDelegate: QuickActionAppDelegate
    #endif
    private let container: ModelContainer
    /// Non-nil when the primary ModelContainer failed and an in-memory fallback is in use.
    private let containerError: (any Error)?
    private let taskService: TaskService
    private let projectService: ProjectService
    private let commentService: CommentService
    private let milestoneService: MilestoneService
    private let maintenanceService: DisplayIDMaintenanceService
    private let displayIDAllocator: DisplayIDAllocator
    private let milestoneIDAllocator: DisplayIDAllocator
    #if os(macOS)
    private let backupScheduler: BackupScheduler
    #endif
    private let syncManager: SyncManager
    private let connectivityMonitor: ConnectivityMonitor
    private let consolidationHistoryReader: TaskConsolidationNativeReader
    private let readCoordinator: MCPReadCoordinator
    #if os(macOS)
    private let mcpSettings: MCPSettings
    private let mcpServer: MCPServer
    private let mcpWriteCoordinator: MCPWriteCoordinator
    #endif
    #if os(iOS)
    private let quickActionService: QuickActionService
    #endif
    /// Resolve before constructing SyncManager, a container, or receipt sidecars.
    private static let persistenceMode = AppPersistencePolicy.current
    private static var uiTestScenario: UITestScenario? {
        UITestScenario(rawValue: ProcessInfo.processInfo.environment["TRANSIT_UI_TEST_SCENARIO"] ?? "")
    }
    // swiftlint:disable:next function_body_length
    init() {
        let mode = Self.persistenceMode
        let debugCloudEnabled = AppPersistencePolicy.developmentCloudSyncEnabled
        let cloudAllowed = mode.permitsCloudSync && (mode == .production || debugCloudEnabled)
        let syncManager = SyncManager(cloudSyncAllowed: cloudAllowed, mode: mode)
        self.syncManager = syncManager
        let schema = Schema([
            Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self, MCPWriteReceipt.self,
            TaskLinkOccurrence.self, TaskLinkRemovalEvidence.self, TaskConsolidationEvent.self
        ])
        let config: ModelConfiguration
        do {
            config = try syncManager.makeModelConfiguration(schema: schema)
        } catch {
            fatalError("Unable to create isolated storage: \(error)")
        }
        AppIsolationSmoke.preflight(mode: mode, configuration: config)
        let containerResult = ContainerFactory.makeContainer(schema: schema, configuration: config)
        // A fallback container is always CloudKit-free, even if the requested
        // configuration enabled sync. Derive and record the effective mode only
        // after the factory has selected the live container [T-1936].
        let cloudSyncActive = CloudSyncBootstrap.effectiveActiveCloudSync(
            requestedCloudSyncActive: syncManager.isCloudSyncActive,
            containerOutcome: containerResult
        )
        syncManager.recordActiveCloudSync(cloudSyncActive)
        let container = containerResult.container
        self.container = container
        self.containerError = containerResult.error
        _showContainerError = State(initialValue: containerResult.error != nil)
        // Single persistence-availability signal, derived once from the container outcome and
        // consulted by both automation surfaces. The in-app alert above only reaches an
        // interactive user; MCP clients and Shortcuts/CLI callers rely on this flag to learn
        // that their writes would not survive a restart [T-1818, T-1836].
        let persistence = PersistenceAvailability.shared
        persistence.update(from: containerResult)
        if mode.permitsCloudSync && containerResult.error == nil {
            syncManager.initializeCloudKitSchemaIfNeeded(container: container)
        }
        #if os(macOS)
        self.backupScheduler = BackupScheduler(service: DatabaseBackupService(container: container))
        #endif
        let context = container.mainContext
        TaskLinkEvidenceMaintenance.atStartup(container: container, mode: mode, persistence: persistence)
        let allocators = AppDisplayIDAllocators.make(mode: mode, syncActive: cloudSyncActive)
        let allocator = allocators.tasks
        self.displayIDAllocator = allocator
        let milestoneAllocator = allocators.milestones
        self.milestoneIDAllocator = milestoneAllocator
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        self.taskService = taskService
        self.projectService = projectService
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)
        self.milestoneService = milestoneService
        let connectivityMonitor = ConnectivityMonitor()
        self.connectivityMonitor = connectivityMonitor
        if mode.permitsCloudSync {
            // Wire up connectivity restore to trigger display ID promotion.
            // The closure is @MainActor @Sendable, and context (container.mainContext)
            // is MainActor-isolated, so it can be captured directly.
            // Only wired when the container is CloudKit-backed: with sync off, regaining
            // connectivity must not start reaching for the CloudKit counter [T-1797].
            if cloudSyncActive {
                connectivityMonitor.onRestore = { @Sendable in
                    _ = try? projectService.reconcileDuplicateNames()
                    await allocator.promoteProvisionalTasks(in: context)
                    await milestoneService.promoteProvisionalMilestones()
                }
            }
            connectivityMonitor.start()
        }
        let commentService = CommentService(modelContext: context)
        self.commentService = commentService
        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: allocator,
            milestoneAllocator: milestoneAllocator,
            commentService: commentService
        )
        self.maintenanceService = maintenanceService
        AppDependencyManager.shared.add(dependency: taskService)
        AppDependencyManager.shared.add(dependency: projectService)
        AppDependencyManager.shared.add(dependency: commentService)
        AppDependencyManager.shared.add(dependency: milestoneService)
        AppDependencyManager.shared.add(dependency: maintenanceService)
        let readDomain = MCPReadPublicationDomain()
        let readCoordinator = MCPReadCoordinator(domain: readDomain, diagnostics: .application)
        self.readCoordinator = readCoordinator
        self.consolidationHistoryReader = TaskConsolidationNativeReader(
            container: container, coordinator: readCoordinator)
        #if os(iOS)
        let quickActionService = QuickActionService()
        self.quickActionService = quickActionService
        appDelegate.quickActionService = quickActionService
        #endif
        #if os(macOS)
        let mcpSettings = MCPSettings(mode: mode)
        self.mcpSettings = mcpSettings
        let writeServices = MCPWriteCommandServices(
            tasks: taskService, projects: projectService,
            comments: commentService, milestones: milestoneService, context: context)
        // Own the retry scope and lock for the app lifetime, across listener restarts.
        let sidecar = mode.usesMemoryStore
            ? FileManager.default.temporaryDirectory.appendingPathComponent("mcp-tests-" + UUID().uuidString)
            : config.url.appendingPathExtension("mcp-writes")
        AppIsolationSmoke.record(mode: mode, container: container, cloudSyncActive: cloudSyncActive,
                                 allocators: allocators, sidecar: sidecar)
        let writeCoordinator = MCPWriteCoordinator(services: writeServices,
            sidecarDirectory: sidecar, persistence: persistence)
        self.mcpWriteCoordinator = writeCoordinator
        try? writeCoordinator.cleanupExpiredOutcomes()

        let reads = MCPReadAppDependencies.make(container: container, syncActive: cloudSyncActive, domain: readDomain)
        let consolidation = MCPConsolidationAppCapability(container: container, reads: reads,
            coordinator: writeCoordinator, taskAllocator: allocator, milestoneAllocator: milestoneAllocator)
        let mcpToolHandler = MCPToolHandler(
            taskService: taskService, projectService: projectService,
            commentService: commentService, milestoneService: milestoneService,
            maintenanceService: maintenanceService, settings: mcpSettings,
            persistence: persistence, taskQuerySnapshots: reads.snapshots, writeCoordinator: writeCoordinator,
            readService: reads, consolidationPreviewAdapter: consolidation?.previews,
            consolidationWriteAdapter: consolidation?.writes, readCoordinator: readCoordinator,
                batchContainer: container,
            taskLinkWriteAdapter: TaskLinkWriteAdapter(taskAllocator: allocator, milestoneAllocator: milestoneAllocator)
        )
        let server = MCPServer(toolHandler: mcpToolHandler, readCoordinator: readCoordinator)
        self.mcpServer = server
        Self.installBackupMaintenance(container: container, syncManager: syncManager,
            connectivityMonitor: connectivityMonitor, server: server, coordinator: writeCoordinator)
        #else
        Self.installBackupMaintenance(container: container, syncManager: syncManager,
            connectivityMonitor: connectivityMonitor)
        #endif
    }
    @State private var showContainerError: Bool
    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @Environment(\.colorScheme) private var colorScheme
    private var currentTheme: AppTheme {
        AppTheme(rawValue: appTheme) ?? .followSystem
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if DatabaseMaintenanceGate.shared.requiresRestart {
                    BackupCompletionView(gate: .shared)
                } else {
                    primaryContent
                }
            }
            .task { seedUITestDataIfNeeded() }
        }
        .modelContainer(container)

        #if os(macOS)
        .commands {
            NewTaskCommand()
            SettingsCommand()
        }
        #endif
        #if os(macOS)
        Window("Settings", id: "settings") {
            withCoreEnvironments(
                SettingsView()
                    .environment(syncManager)
                    .environment(connectivityMonitor)
                    .environment(mcpSettings)
                    .environment(mcpServer)
            )
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 780, height: 500)
        .windowResizability(.contentSize)
        WindowGroup("Task Detail", id: "task-detail", for: UUID.self) { $taskID in
            if let taskID {
                withCoreEnvironments(TaskDetailWindowView(taskID: taskID))
            }
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 600, height: 700)
        Window("New Task", id: "add-task") {
            withCoreEnvironments(AddTaskSheet())
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 600, height: 500)
        #endif
    }
}
extension TransitApp {
    private var primaryContent: some View {
        NavigationStack {
            DashboardView()
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .settings:
                        SettingsView()
                    case .projectCreate:
                        ProjectEditView(project: nil)
                    case .projectEdit(let project):
                        ProjectEditView(project: project)
                    case .milestoneEdit(let project, let milestone):
                        MilestoneEditView(project: project, milestone: milestone)
                    case .report:
                        ReportView()
                    case .acknowledgments:
                        AcknowledgmentsView()
                    case .licenseText:
                        LicenseTextView()
                    case .backups:
                        DatabaseBackupView()
                    case .dataMaintenance:
                        DataMaintenanceView()
                    }
                }
        }
        .disabled(DatabaseMaintenanceGate.shared.requiresRestart)
        .preferredColorScheme(currentTheme.preferredColorScheme)
        .environment(\.resolvedTheme, currentTheme.resolved(with: colorScheme))
        .modifier(ScenePhaseModifier(
            displayIDAllocator: displayIDAllocator,
            projectService: projectService,
            milestoneService: milestoneService,
            modelContext: container.mainContext
        ))
        .environment(taskService)
        .environment(projectService)
        .environment(commentService)
        .environment(milestoneService)
        .environment(maintenanceService)
        .disabled(DatabaseMaintenanceGate.shared.requiresRestart)
        .environment(\.consolidationHistoryReader, consolidationHistoryReader)
        .environment(syncManager)
        .environment(connectivityMonitor)
        #if os(iOS)
        .environment(quickActionService)
        .readSceneSession()
        #endif
        #if os(macOS)
        .environment(mcpSettings)
        .environment(mcpServer)
        .task {
            if Self.persistenceMode.permitsBackgroundServices { backupScheduler.start() }
            await startMCPServerIfEnabled()
        }
        #endif
        .alert(
            "Unable to Load Data",
            isPresented: $showContainerError
        ) {
            Button("OK") {}
        } message: {
            Text(
                "Transit couldn't open its database and is running with temporary storage. "
                + "Your existing data is not lost — try restarting the app. "
                + "If the problem persists, check available device storage."
            )
        }
    }
    // MARK: - Shared Environment
    @ViewBuilder private func withCoreEnvironments<V: View>(_ view: V) -> some View {
        if DatabaseMaintenanceGate.shared.requiresRestart {
            BackupCompletionView(gate: .shared)
        } else {
            view
                .disabled(DatabaseMaintenanceGate.shared.requiresRestart)
                .preferredColorScheme(currentTheme.preferredColorScheme)
                .environment(\.resolvedTheme, currentTheme.resolved(with: colorScheme))
                .environment(taskService)
                .environment(projectService)
                .environment(commentService)
                .environment(milestoneService)
                .environment(maintenanceService)
                .disabled(DatabaseMaintenanceGate.shared.requiresRestart)
                .environment(\.consolidationHistoryReader, consolidationHistoryReader)
        }
    }
    // MARK: - UI Test Support
    private func seedUITestDataIfNeeded() {
        guard let scenario = Self.uiTestScenario else { return }
        if scenario == .backupCompletion {
            guard Self.persistenceMode.usesMemoryStore, !DatabaseMaintenanceGate.shared.requiresRestart else { return }
            do {
                let recovery = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SyntheticRecovery-\(UUID()).transitbackup")
                let archive = try DatabaseArchive.capture(ModelContext(container))
                _ = try DatabaseBackupIO.export(archive, to: recovery)
                DatabaseMaintenanceGate.shared.install(container: container, prepare: { [] }, finish: {})
                try DatabaseMaintenanceGate.shared.didReplace(
                    container, availability: .shared, recoveryBackupURL: recovery)
            } catch { preconditionFailure("Synthetic recovery fixture failed: \(error)") }
            return
        }
        scenario.seed(into: container.mainContext)
    }
}
extension TransitApp {
    // MARK: - MCP Server
    #if os(macOS)
    private func startMCPServerIfEnabled() async {
        // Skip MCP server in unit test host to avoid port conflicts across test runs
        guard Self.persistenceMode.permitsAutomaticMCPStartup, mcpSettings.isEnabled else { return }
        await mcpServer.start(port: mcpSettings.port)
        syncManager.startHeartbeat(container: container)
    }
    #endif
}
