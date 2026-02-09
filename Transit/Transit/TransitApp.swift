import AppIntents
import CloudKit
import SwiftData
import SwiftUI

@main
struct TransitApp: App {

    private let container: ModelContainer
    private let taskService: TaskService
    private let projectService: ProjectService
    private let displayIDAllocator: DisplayIDAllocator
    private let syncManager: SyncManager
    private let connectivityMonitor: ConnectivityMonitor

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    init() {
        let syncManager = SyncManager()
        self.syncManager = syncManager

        let schema = Schema([Project.self, TransitTask.self])
        let config: ModelConfiguration
        if Self.isUITesting {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            config = syncManager.makeModelConfiguration(schema: schema)
        }
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.container = container

        if !Self.isUITesting {
            syncManager.initializeCloudKitSchemaIfNeeded(container: container)
        }

        let context = ModelContext(container)
        let allocator = DisplayIDAllocator(container: CKContainer.default())
        self.displayIDAllocator = allocator

        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        self.taskService = taskService
        self.projectService = projectService

        let connectivityMonitor = ConnectivityMonitor()
        self.connectivityMonitor = connectivityMonitor

        // Wire up connectivity restore to trigger display ID promotion.
        connectivityMonitor.onRestore = { @Sendable in
            await allocator.promoteProvisionalTasks(in: context)
        }
        connectivityMonitor.start()

        AppDependencyManager.shared.add(dependency: taskService)
        AppDependencyManager.shared.add(dependency: projectService)
    }

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
                        }
                    }
            }
            .modifier(ScenePhaseModifier(
                displayIDAllocator: displayIDAllocator,
                modelContext: ModelContext(container)
            ))
            .environment(taskService)
            .environment(projectService)
            .environment(syncManager)
            .environment(connectivityMonitor)
            .task { seedUITestDataIfNeeded() }
        }
        .modelContainer(container)
    }

    // MARK: - UI Test Support

    private func seedUITestDataIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting-seed-data") else { return }
        let project = projectService.createProject(
            name: "Test Project", description: "UI test project", gitRepo: nil, colorHex: "#FF5733"
        )
        let task = TransitTask(
            name: "Sample Task", description: "A test task", type: .feature,
            project: project, displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(task)
        container.mainContext.insert(task)

        let abandonedTask = TransitTask(
            name: "Abandoned Task", description: nil, type: .chore,
            project: project, displayID: .permanent(2)
        )
        StatusEngine.initializeNewTask(abandonedTask)
        StatusEngine.applyTransition(task: abandonedTask, to: .abandoned)
        container.mainContext.insert(abandonedTask)
    }
}

// MARK: - Scene Phase Tracking

/// Observes scenePhase from within a View context (required by SwiftUI) and
/// triggers display ID promotion on app launch and return to foreground.
private struct ScenePhaseModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let displayIDAllocator: DisplayIDAllocator
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .task {
                await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                    }
                }
            }
    }
}
