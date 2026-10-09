import Foundation
import SwiftData

@main
struct BootstrapProbe {
    // swiftlint:disable:next function_body_length
    @MainActor static func main() async throws {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                             SyncHeartbeat.self, MCPWriteReceipt.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let project = Project(name: "Synthetic", description: "Bootstrap probe",
                              gitRepo: nil, colorHex: "#123456")
        let task = TransitTask(name: "Provisional", type: .feature, project: project,
                               displayID: .provisional)
        context.insert(project)
        context.insert(task)
        try context.save()
        var calls: [String] = []
        let factory: (String, String) -> DisplayIDAllocator = { name, container in
            calls.append(container + ":" + name)
            return DisplayIDAllocator(store: DisabledCounterStore(), isCloudSyncActive: true)
        }
        for mode in [AppPersistencePolicy.Mode.development, .unitTest, .uiTest, .production] {
            for active in [false, true] where !mode.permitsCloudSync || !active {
                let pair = AppDisplayIDAllocators.make(mode: mode, syncActive: active, cloudFactory: factory)
                for allocator in [pair.tasks, pair.milestones] {
                    precondition(!allocator.isCloudSyncActive)
                    precondition(allocator.counterStore is DisabledCounterStore)
                    do {
                        _ = try await allocator.allocateNextID()
                        fatalError("Inactive allocation succeeded")
                    } catch DisplayIDAllocator.Error.cloudSyncInactive {} catch { throw error }
                    do {
                        _ = try await allocator.counterStore.loadCounter()
                        fatalError("Disabled counter read succeeded")
                    } catch DisabledCounterStore.Failure.unavailable {} catch { throw error }
                    do {
                        try await allocator.counterStore.saveCounter(nextDisplayID: 2, expectedChangeTag: nil)
                        fatalError("Disabled counter write succeeded")
                    } catch DisabledCounterStore.Failure.unavailable {} catch { throw error }
                    await allocator.promoteProvisionalTasks(in: context, save: { _ in
                        fatalError("Inactive promotion tried to save")
                    })
                    precondition(task.permanentDisplayId == nil)
                }
                precondition(calls.isEmpty)
            }
        }
        let production = AppDisplayIDAllocators.make(mode: .production, syncActive: true,
                                                     cloudFactory: factory)
        precondition(production.tasks.isCloudSyncActive && production.milestones.isCloudSyncActive)
        precondition(calls == ["iCloud.me.nore.ig.Transit:global-counter",
                               "iCloud.me.nore.ig.Transit:milestone-counter"])
        calls.removeAll()
        let development = AppDisplayIDAllocators.make(mode: .development, syncActive: true, cloudFactory: factory)
        precondition(development.tasks.isCloudSyncActive && development.milestones.isCloudSyncActive)
        precondition(calls == ["iCloud.me.nore.ig.Transit.development:global-counter",
                               "iCloud.me.nore.ig.Transit.development:milestone-counter"])
        print("Bootstrap passed: isolated factory calls=0; active production counter names preserved")
    }
}
