import Network
#if canImport(AppIntents)
import AppIntents
#endif
import Combine
import SwiftData
import SwiftUI

@main
struct TransitApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("syncEnabled") private var syncEnabled = true
    @StateObject private var runtime: TransitAppRuntime

    init() {
        let initialSyncEnabled = UserDefaults.standard.object(forKey: "syncEnabled") as? Bool ?? true
        _runtime = StateObject(wrappedValue: TransitAppRuntime(initialSyncEnabled: initialSyncEnabled))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
            }
            .id(runtime.containerGeneration)
            .environment(runtime.taskService)
            .environment(runtime.projectService)
            .task {
                runtime.startConnectivityMonitoring()
                await runtime.promoteProvisionalTasks()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await runtime.promoteProvisionalTasks()
                }
            }
            .onChange(of: syncEnabled) { _, isEnabled in
                runtime.reconfigureCloudSync(isEnabled: isEnabled)
            }
        }
        .modelContainer(runtime.modelContainer)
    }
}

@MainActor
final class TransitAppRuntime: ObservableObject {
    @Published private(set) var modelContainer: ModelContainer
    @Published private(set) var taskService: TaskService
    @Published private(set) var projectService: ProjectService
    @Published private(set) var containerGeneration = UUID()

    private let schema = Schema([Project.self, TransitTask.self])
    private let monitorQueue = DispatchQueue(label: "me.nore.ig.Transit.network-monitor")
    private var cloudSyncEnabled: Bool
    private var modelContext: ModelContext
    private var displayIDAllocator: DisplayIDAllocator
    private var isPromoting = false
    private var connectivityMonitor: NWPathMonitor?
    private var lastConnectivitySatisfied = false

    init(initialSyncEnabled: Bool) {
        cloudSyncEnabled = initialSyncEnabled

        let container = Self.makeModelContainer(schema: schema, syncEnabled: initialSyncEnabled)
        modelContainer = container

        let context = ModelContext(container)
        modelContext = context

        let allocator = DisplayIDAllocator()
        displayIDAllocator = allocator

        taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        projectService = ProjectService(modelContext: context)

        registerDependencies()
    }

    deinit {
        connectivityMonitor?.cancel()
    }

    func startConnectivityMonitoring() {
        guard connectivityMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let isSatisfied = path.status == .satisfied
                defer {
                    lastConnectivitySatisfied = isSatisfied
                }

                if isSatisfied && !lastConnectivitySatisfied {
                    await promoteProvisionalTasks()
                }
            }
        }
        monitor.start(queue: monitorQueue)

        lastConnectivitySatisfied = monitor.currentPath.status == .satisfied
        connectivityMonitor = monitor
    }

    func promoteProvisionalTasks() async {
        guard !isPromoting else { return }

        isPromoting = true
        defer { isPromoting = false }
        await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
    }

    func reconfigureCloudSync(isEnabled: Bool) {
        guard cloudSyncEnabled != isEnabled else { return }
        cloudSyncEnabled = isEnabled

        let container = Self.makeModelContainer(schema: schema, syncEnabled: isEnabled)
        let context = ModelContext(container)
        let allocator = DisplayIDAllocator()
        let task = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = ProjectService(modelContext: context)

        modelContainer = container
        modelContext = context
        displayIDAllocator = allocator
        taskService = task
        projectService = project
        containerGeneration = UUID()

        registerDependencies()

        if isEnabled {
            Task {
                await promoteProvisionalTasks()
            }
        }
    }

    private func registerDependencies() {
#if canImport(AppIntents)
        let taskService = self.taskService
        let projectService = self.projectService
        AppDependencyManager.shared.add(dependency: taskService)
        AppDependencyManager.shared.add(dependency: projectService)
#endif
    }

    private static func makeModelContainer(schema: Schema, syncEnabled: Bool) -> ModelContainer {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
                fatalError("Failed to initialize in-memory model container for tests")
            }
            return container
        }

        if syncEnabled {
            let cloudKitConfiguration = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.me.nore.ig.Transit")
            )

            if let container = try? ModelContainer(for: schema, configurations: [cloudKitConfiguration]) {
                return container
            }
        }

        let localConfiguration = ModelConfiguration()
        guard let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
            fatalError("Failed to initialize model container")
        }
        return container
    }
}
