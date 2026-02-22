import AppIntents
import CloudKit
import SwiftData
import SwiftUI

@main
struct TransitApp: App {

    private let container: ModelContainer
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

    private static var uiTestScenario: UITestScenario? {
        UITestScenario(rawValue: ProcessInfo.processInfo.environment["TRANSIT_UI_TEST_SCENARIO"] ?? "")
    }

    init() {
        let syncManager = SyncManager()
        self.syncManager = syncManager

        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let config: ModelConfiguration
        if Self.uiTestScenario != nil {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            config = syncManager.makeModelConfiguration(schema: schema)
        }
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.container = container

        if Self.uiTestScenario == nil {
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

        // Wire up connectivity restore to trigger display ID promotion.
        connectivityMonitor.onRestore = { @Sendable in
            await allocator.promoteProvisionalTasks(in: context)
            await milestoneService.promoteProvisionalMilestones()
        }
        connectivityMonitor.start()

        let commentService = CommentService(modelContext: context)
        self.commentService = commentService

        AppDependencyManager.shared.add(dependency: taskService)
        AppDependencyManager.shared.add(dependency: projectService)
        AppDependencyManager.shared.add(dependency: commentService)
        AppDependencyManager.shared.add(dependency: milestoneService)

        #if os(macOS)
        let mcpSettings = MCPSettings()
        self.mcpSettings = mcpSettings
        let mcpToolHandler = MCPToolHandler(
            taskService: taskService, projectService: projectService,
            commentService: commentService, milestoneService: milestoneService
        )
        self.mcpServer = MCPServer(toolHandler: mcpToolHandler)
        #endif
    }

    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .settings:
                            SettingsView()
                        case .projectEdit(let project):
                            ProjectEditView(project: project)
                        case .milestoneEdit(let project, let milestone):
                            MilestoneEditView(project: project, milestone: milestone)
                        case .report:
                            ReportView()
                        }
                    }
            }
            .preferredColorScheme(
                (AppTheme(rawValue: appTheme) ?? .followSystem).preferredColorScheme
            )
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
            #if os(macOS)
            .environment(mcpSettings)
            .environment(mcpServer)
            .task { startMCPServerIfEnabled() }
            #endif
            .task { seedUITestDataIfNeeded() }
        }
        .modelContainer(container)
    }

    // MARK: - MCP Server

    #if os(macOS)
    private func startMCPServerIfEnabled() {
        guard mcpSettings.isEnabled else { return }
        mcpServer.start(port: mcpSettings.port)
    }
    #endif

    // MARK: - UI Test Support

    private func seedUITestDataIfNeeded() {
        guard let scenario = Self.uiTestScenario else { return }
        switch scenario {
        case .empty:
            return
        case .board:
            seedBoardScenario()
        }
    }

    private func seedBoardScenario() {
        let now = Date()
        let ctx = container.mainContext

        let alpha = Project(
            name: "Alpha", description: "Primary project", gitRepo: nil, colorHex: "#0A84FF"
        )
        let beta = Project(
            name: "Beta", description: "Secondary project", gitRepo: nil, colorHex: "#30D158"
        )
        ctx.insert(alpha)
        ctx.insert(beta)

        let shipActive = TransitTask(
            name: "Ship Active", description: nil, type: .feature, project: alpha, displayID: .permanent(1)
        )
        shipActive.creationDate = now.addingTimeInterval(-120)
        shipActive.lastStatusChangeDate = now.addingTimeInterval(-60)
        shipActive.statusRawValue = TaskStatus.inProgress.rawValue
        ctx.insert(shipActive)

        let backlogIdea = TransitTask(
            name: "Backlog Idea", description: nil, type: .research, project: alpha, displayID: .permanent(2)
        )
        backlogIdea.creationDate = now.addingTimeInterval(-560)
        backlogIdea.lastStatusChangeDate = now.addingTimeInterval(-500)
        backlogIdea.statusRawValue = TaskStatus.idea.rawValue
        ctx.insert(backlogIdea)

        let oldAbandoned = TransitTask(
            name: "Old Abandoned", description: nil, type: .chore, project: alpha, displayID: .permanent(3)
        )
        oldAbandoned.creationDate = now.addingTimeInterval(-360)
        oldAbandoned.lastStatusChangeDate = now.addingTimeInterval(-300)
        oldAbandoned.statusRawValue = TaskStatus.abandoned.rawValue
        oldAbandoned.completionDate = now.addingTimeInterval(-300)
        ctx.insert(oldAbandoned)

        let betaReview = TransitTask(
            name: "Beta Review", description: nil, type: .bug, project: beta, displayID: .permanent(4)
        )
        betaReview.creationDate = now.addingTimeInterval(-260)
        betaReview.lastStatusChangeDate = now.addingTimeInterval(-200)
        betaReview.statusRawValue = TaskStatus.readyForReview.rawValue
        ctx.insert(betaReview)

        // Sample milestones
        let alphaV1 = Milestone(name: "v1.0", description: "First release", project: alpha, displayID: .permanent(1))
        ctx.insert(alphaV1)
        shipActive.milestone = alphaV1
        backlogIdea.milestone = alphaV1

        let betaV1 = Milestone(name: "Beta v1", description: nil, project: beta, displayID: .permanent(2))
        ctx.insert(betaV1)
        betaReview.milestone = betaV1
    }
}

// MARK: - UI Test Scenarios

private enum UITestScenario: String {
    case empty
    case board
}

// MARK: - Scene Phase Tracking

/// Observes scenePhase from within a View context (required by SwiftUI) and
/// triggers display ID promotion on app launch and return to foreground.
private struct ScenePhaseModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let displayIDAllocator: DisplayIDAllocator
    let milestoneService: MilestoneService
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .task {
                await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                await milestoneService.promoteProvisionalMilestones()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                        await milestoneService.promoteProvisionalMilestones()
                    }
                }
            }
    }
}
