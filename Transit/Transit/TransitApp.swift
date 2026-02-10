//
//  TransitApp.swift
//  Transit
//
//  App entry point with ModelContainer, service instantiation, and environment injection.
//

import CloudKit
import Network
import SwiftData
import SwiftUI

@main
struct TransitApp: App {
    let container: ModelContainer
    let taskService: TaskService
    let projectService: ProjectService
    let displayIDAllocator: DisplayIDAllocator

    @State private var pathMonitor: NWPathMonitor?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Configure SwiftData with CloudKit sync
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(
            cloudKitDatabase: .private("iCloud.com.example.transit")
        )

        do {
            let modelContainer = try ModelContainer(for: schema, configurations: [config])
            self.container = modelContainer

            // Create main context for services
            let context = ModelContext(modelContainer)

            // Instantiate services
            let allocator = DisplayIDAllocator(container: CKContainer.default())
            let taskSvc = TaskService(modelContext: context, displayIDAllocator: allocator)
            let projectSvc = ProjectService(modelContext: context)

            self.taskService = taskSvc
            self.projectService = projectSvc
            self.displayIDAllocator = allocator

            // TODO: Register services for App Intents @Dependency resolution
            // This will be implemented in the App Intents phase
            // AppDependencyManager.shared.add(dependency: taskSvc)
            // AppDependencyManager.shared.add(dependency: projectSvc)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .modelContainer(container)
                .environment(taskService)
                .environment(projectService)
                .task {
                    // Promote provisional tasks on app launch
                    await promoteProvisionalTasks()

                    // Start connectivity monitoring
                    startConnectivityMonitoring()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Promote provisional tasks when app becomes active
                        Task {
                            await promoteProvisionalTasks()
                        }
                    }
                }
        }
    }

    private func promoteProvisionalTasks() async {
        do {
            try await displayIDAllocator.promoteProvisionalTasks(in: container.mainContext)
        } catch {
            // Promotion will retry on next trigger (app launch, foreground, connectivity)
            // swiftlint:disable:next no_print
            print("Failed to promote provisional tasks: \(error)")
        }
    }

    private func startConnectivityMonitoring() {
        let monitor = NWPathMonitor()
        let allocator = displayIDAllocator
        let mainContext = container.mainContext

        monitor.pathUpdateHandler = { path in
            // Trigger promotion when connectivity is satisfied
            if path.status == .satisfied {
                Task { @MainActor in
                    do {
                        try await allocator.promoteProvisionalTasks(in: mainContext)
                    } catch {
                        // Promotion will retry on next trigger
                        // swiftlint:disable:next no_print
                        print("Failed to promote provisional tasks on connectivity restore: \(error)")
                    }
                }
            }
        }

        monitor.start(queue: DispatchQueue.global(qos: .utility))
        pathMonitor = monitor
    }
}
