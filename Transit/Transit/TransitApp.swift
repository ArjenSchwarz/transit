import SwiftData
import SwiftUI

@main
struct TransitApp: App {
    private let modelContainer: ModelContainer
    private let taskService: TaskService
    private let projectService: ProjectService

    init() {
        let schema = Schema([
            Project.self,
            TransitTask.self
        ])
        let container = Self.makeModelContainer(schema: schema)
        modelContainer = container

        let context = ModelContext(container)
        let displayIDAllocator = DisplayIDAllocator()
        taskService = TaskService(modelContext: context, displayIDAllocator: displayIDAllocator)
        projectService = ProjectService(modelContext: context)
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(taskService)
                .environment(projectService)
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
                fatalError("Failed to initialize in-memory model container for tests")
            }
            return container
        }

        let cloudKitConfiguration = ModelConfiguration(
            cloudKitDatabase: .private("iCloud.me.nore.ig.Transit")
        )

        if let container = try? ModelContainer(for: schema, configurations: [cloudKitConfiguration]) {
            return container
        }

        // Fall back to local storage if CloudKit container setup fails.
        let localConfiguration = ModelConfiguration()
        guard let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
            fatalError("Failed to initialize model container")
        }
        return container
    }
}
