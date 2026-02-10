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
    private let storeURL = TransitAppRuntime.persistentStoreURL()
    private let monitorQueue = DispatchQueue(label: "me.nore.ig.Transit.network-monitor")
    private var cloudSyncEnabled: Bool
    private var modelContext: ModelContext
    private var displayIDAllocator: DisplayIDAllocator
    private var isPromoting = false
    private var connectivityMonitor: NWPathMonitor?
    private var lastConnectivitySatisfied = false
    private var didSeedUITestData = false

    init(initialSyncEnabled: Bool) {
        cloudSyncEnabled = initialSyncEnabled

        let container = Self.makeModelContainer(
            schema: schema,
            syncEnabled: initialSyncEnabled,
            storeURL: storeURL
        )
        modelContainer = container

        let context = ModelContext(container)
        modelContext = context

        let allocator = DisplayIDAllocator()
        displayIDAllocator = allocator

        taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        projectService = ProjectService(modelContext: context)

        bootstrapUITestDataIfNeeded()
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

        // SwiftData does not expose runtime mutation of cloudKitContainerOptions.
        // Re-opening the same store with CloudKit enabled/disabled is the equivalent
        // nil/restore behavior and preserves persistent history for delta sync.
        let container = Self.makeModelContainer(
            schema: schema,
            syncEnabled: isEnabled,
            storeURL: storeURL
        )
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

    private func bootstrapUITestDataIfNeeded() {
        guard !didSeedUITestData else { return }
        guard let scenario = UITestScenario(
            rawValue: ProcessInfo.processInfo.environment["TRANSIT_UI_TEST_SCENARIO"] ?? ""
        ) else { return }

        didSeedUITestData = true

        switch scenario {
        case .empty:
            return
        case .board:
            seedBoardScenario()
        }
    }

    private func seedBoardScenario() {
        let now = Date()
        let alpha = makeUITestProject(
            id: "11111111-1111-1111-1111-111111111111",
            name: "Alpha",
            description: "Primary",
            colorHex: "#0A84FF"
        )
        let beta = makeUITestProject(
            id: "22222222-2222-2222-2222-222222222222",
            name: "Beta",
            description: "Secondary",
            colorHex: "#30D158"
        )

        modelContext.insert(alpha)
        modelContext.insert(beta)

        let taskSeeds = makeBoardUITestTaskSeeds(alpha: alpha, beta: beta)
        taskSeeds
            .map { makeUITestTask(from: $0, now: now) }
            .forEach(modelContext.insert)

        try? modelContext.save()
    }

    private static func makeModelContainer(
        schema: Schema,
        syncEnabled: Bool,
        storeURL: URL
    ) -> ModelContainer {
        let environment = ProcessInfo.processInfo.environment
        let isTestContext = environment["XCTestConfigurationFilePath"] != nil
            || environment["TRANSIT_UI_TEST_SCENARIO"] != nil
        if isTestContext {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
                fatalError("Failed to initialize in-memory model container for tests")
            }
            return container
        }

        if syncEnabled {
            let cloudKitConfiguration = ModelConfiguration(
                url: storeURL,
                cloudKitDatabase: .private("iCloud.me.nore.ig.Transit")
            )

            if let container = try? ModelContainer(for: schema, configurations: [cloudKitConfiguration]) {
                return container
            }
        }

        let localConfiguration = ModelConfiguration(url: storeURL)
        guard let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
            fatalError("Failed to initialize model container")
        }
        return container
    }

    static func persistentStoreURL(fileManager: FileManager = .default) -> URL {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let directory = appSupport.appendingPathComponent("Transit", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Transit.store")
    }
}

private struct UITestTaskSeed {
    let id: String
    let displayID: Int
    let name: String
    let description: String
    let status: TaskStatus
    let type: TaskType
    let creationOffset: TimeInterval
    let statusChangeOffset: TimeInterval
    let completionOffset: TimeInterval?
    let project: Project
}

private func makeUITestProject(id: String, name: String, description: String, colorHex: String) -> Project {
    Project(
        id: UUID(uuidString: id) ?? UUID(),
        name: name,
        description: description,
        colorHex: colorHex
    )
}

private func makeUITestTask(from seed: UITestTaskSeed, now: Date) -> TransitTask {
    TransitTask(
        id: UUID(uuidString: seed.id) ?? UUID(),
        permanentDisplayId: seed.displayID,
        name: seed.name,
        description: seed.description,
        status: seed.status,
        type: seed.type,
        creationDate: now.addingTimeInterval(seed.creationOffset),
        lastStatusChangeDate: now.addingTimeInterval(seed.statusChangeOffset),
        completionDate: seed.completionOffset.map { now.addingTimeInterval($0) },
        project: seed.project
    )
}

private func makeBoardUITestTaskSeeds(alpha: Project, beta: Project) -> [UITestTaskSeed] {
    [
        UITestTaskSeed(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            displayID: 1,
            name: "Ship Active",
            description: "In progress task",
            status: .inProgress,
            type: .feature,
            creationOffset: -120,
            statusChangeOffset: -60,
            completionOffset: nil,
            project: alpha
        ),
        UITestTaskSeed(
            id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            displayID: 2,
            name: "Backlog Idea",
            description: "Idea task",
            status: .idea,
            type: .research,
            creationOffset: -600,
            statusChangeOffset: -500,
            completionOffset: nil,
            project: alpha
        ),
        UITestTaskSeed(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            displayID: 3,
            name: "Old Abandoned",
            description: "Abandoned task",
            status: .abandoned,
            type: .chore,
            creationOffset: -400,
            statusChangeOffset: -300,
            completionOffset: -300,
            project: alpha
        ),
        UITestTaskSeed(
            id: "dddddddd-dddd-dddd-dddd-dddddddddddd",
            displayID: 4,
            name: "Beta Review",
            description: "Ready for review",
            status: .readyForReview,
            type: .bug,
            creationOffset: -240,
            statusChangeOffset: -200,
            completionOffset: nil,
            project: beta
        )
    ]
}

private enum UITestScenario: String {
    case empty
    case board
}
