import AppIntents
import CloudKit
import SwiftData
import SwiftUI

@main
struct TransitApp: App {

    private let container: ModelContainer
    private let taskService: TaskService
    private let projectService: ProjectService

    init() {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.me.nore.ig.Transit")
        )
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.container = container

        let context = ModelContext(container)
        let allocator = DisplayIDAllocator(container: CKContainer.default())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        self.taskService = taskService
        self.projectService = projectService

        AppDependencyManager.shared.add(dependency: taskService)
        AppDependencyManager.shared.add(dependency: projectService)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
            }
            .environment(taskService)
            .environment(projectService)
        }
        .modelContainer(container)
    }
}
