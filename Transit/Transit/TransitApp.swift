import AppIntents
import CloudKit
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
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
    private let displayIDAllocator: DisplayIDAllocator
    private let milestoneIDAllocator: DisplayIDAllocator
    private let syncManager: SyncManager
    private let connectivityMonitor: ConnectivityMonitor

    #if os(macOS)
    private let mcpSettings: MCPSettings
    private let mcpServer: MCPServer
    #endif

    #if os(iOS)
    private let quickActionService: QuickActionService
    #endif

    /// True when the app is launched as a unit test host (not UI tests, which set their own scenario).
    private static let isUnitTestHost: Bool = NSClassFromString("XCTestCase") != nil
        && ProcessInfo.processInfo.environment["TRANSIT_UI_TEST_SCENARIO"] == nil

    private static var uiTestScenario: UITestScenario? {
        UITestScenario(rawValue: ProcessInfo.processInfo.environment["TRANSIT_UI_TEST_SCENARIO"] ?? "")
    }

    // swiftlint:disable:next function_body_length
    init() {
        let isInert = Self.isUnitTestHost
        let syncManager = SyncManager()
        self.syncManager = syncManager

        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self])
        let config: ModelConfiguration
        if isInert || Self.uiTestScenario != nil {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            config = syncManager.makeModelConfiguration(schema: schema)
        }
        let containerResult = ContainerFactory.makeContainer(schema: schema, configuration: config)
        let container = containerResult.container
        self.container = container
        self.containerError = containerResult.error
        _showContainerError = State(initialValue: containerResult.error != nil)

        if !isInert && Self.uiTestScenario == nil && containerResult.error == nil {
            syncManager.initializeCloudKitSchemaIfNeeded(container: container)
        }

        let context = container.mainContext
        let allocator = DisplayIDAllocator()
        self.displayIDAllocator = allocator

        let milestoneAllocator = DisplayIDAllocator(counterRecordName: "milestone-counter")
        self.milestoneIDAllocator = milestoneAllocator

        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        self.taskService = taskService
        self.projectService = projectService

        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)
        self.milestoneService = milestoneService

        let connectivityMonitor = ConnectivityMonitor()
        self.connectivityMonitor = connectivityMonitor

        if !isInert {
            // Wire up connectivity restore to trigger display ID promotion.
            // The closure is @MainActor @Sendable, and context (container.mainContext)
            // is MainActor-isolated, so it can be captured directly.
            connectivityMonitor.onRestore = { @Sendable in
                await allocator.promoteProvisionalTasks(in: context)
                await milestoneService.promoteProvisionalMilestones()
            }
            connectivityMonitor.start()
        }

        let commentService = CommentService(modelContext: context)
        self.commentService = commentService

        AppDependencyManager.shared.add(dependency: taskService)
        AppDependencyManager.shared.add(dependency: projectService)
        AppDependencyManager.shared.add(dependency: commentService)
        AppDependencyManager.shared.add(dependency: milestoneService)

        #if os(iOS)
        let quickActionService = QuickActionService()
        self.quickActionService = quickActionService
        appDelegate.quickActionService = quickActionService
        #endif

        #if os(macOS)
        let mcpSettings = MCPSettings()
        self.mcpSettings = mcpSettings
        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: allocator,
            taskCounterStore: allocator.counterStore,
            milestoneAllocator: milestoneAllocator,
            milestoneCounterStore: milestoneAllocator.counterStore,
            commentService: commentService
        )
        let mcpToolHandler = MCPToolHandler(
            taskService: taskService, projectService: projectService,
            commentService: commentService, milestoneService: milestoneService,
            maintenanceService: maintenanceService, settings: mcpSettings
        )
        self.mcpServer = MCPServer(toolHandler: mcpToolHandler)
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
                        case .dataMaintenance:
                            DataMaintenanceView()
                        }
                    }
            }
            .preferredColorScheme(currentTheme.preferredColorScheme)
            .environment(\.resolvedTheme, currentTheme.resolved(with: colorScheme))
            .modifier(ScenePhaseModifier(
                displayIDAllocator: displayIDAllocator,
                milestoneService: milestoneService,
                modelContext: container.mainContext
            ))
            .environment(taskService)
            .environment(projectService)
            .environment(commentService)
            .environment(milestoneService)
            .environment(syncManager)
            .environment(connectivityMonitor)
            #if os(iOS)
            .environment(quickActionService)
            .readSceneSession()
            #endif
            #if os(macOS)
            .environment(mcpSettings)
            .environment(mcpServer)
            .task { startMCPServerIfEnabled() }
            #endif
            .task { seedUITestDataIfNeeded() }
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

    // MARK: - Shared Environment

    private func withCoreEnvironments<V: View>(_ view: V) -> some View {
        view
            .preferredColorScheme(currentTheme.preferredColorScheme)
            .environment(\.resolvedTheme, currentTheme.resolved(with: colorScheme))
            .environment(taskService)
            .environment(projectService)
            .environment(commentService)
            .environment(milestoneService)
    }

    // MARK: - MCP Server

    #if os(macOS)
    private func startMCPServerIfEnabled() {
        // Skip MCP server in unit test host to avoid port conflicts across test runs
        guard mcpSettings.isEnabled, !Self.isUnitTestHost else { return }
        mcpServer.start(port: mcpSettings.port)
        syncManager.startHeartbeat(context: container.mainContext)
    }
    #endif

    // MARK: - UI Test Support

    private func seedUITestDataIfNeeded() {
        guard let scenario = Self.uiTestScenario else { return }
        scenario.seed(into: container.mainContext)
    }
}

// MARK: - macOS Commands

#if os(macOS)
private struct NewTaskCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                openWindow(id: "add-task")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

private struct SettingsCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
#endif

// MARK: - Quick Action App Delegate

#if os(iOS)
final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    var quickActionService: QuickActionService?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem, shortcut.type == QuickActionService.newTaskActionType {
            quickActionService?.requestNewTask(
                forSceneSession: connectingSceneSession.persistentIdentifier
            )
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        // Always register scene delegate so warm-start quick actions are delivered
        // via windowScene(_:performActionFor:completionHandler:).
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = shortcutItem.type == QuickActionService.newTaskActionType
        if handled, let appDelegate = UIApplication.shared.delegate as? QuickActionAppDelegate {
            appDelegate.quickActionService?.requestNewTask(
                forSceneSession: windowScene.session.persistentIdentifier
            )
        }
        completionHandler(handled)
    }
}
#endif
