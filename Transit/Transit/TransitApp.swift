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
        let configuration = ModelConfiguration(cloudKitDatabase: .private("iCloud.me.nore.ig.Transit"))
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container

            let context = ModelContext(container)
            let displayIDAllocator = DisplayIDAllocator()
            taskService = TaskService(modelContext: context, displayIDAllocator: displayIDAllocator)
            projectService = ProjectService(modelContext: context)
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(taskService)
                .environment(projectService)
        }
        .modelContainer(modelContainer)
    }
}
