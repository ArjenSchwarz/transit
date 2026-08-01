import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression coverage for T-1797 and T-1857.
///
/// T-1797: when the live `ModelContainer` was created with `cloudKitDatabase: .none`
/// (iCloud Sync off at launch), nothing in the display-ID subsystem may reach the
/// CloudKit counter record. Every test here asserts on `InMemoryCounterStore`
/// access counts — the counter store must be *untouched*, not merely unsuccessful.
///
/// T-1857: the sync preference and the mode the container was actually built with
/// are two different things. `SyncManager` must expose both so Settings can tell the
/// user a change only lands after a relaunch.
@MainActor
@Suite(.serialized)
struct SyncDisabledGatingTests {

    // MARK: - Helpers

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    /// Saves and restores the "syncEnabled" default around a body that mutates it.
    private func withSavedDefaults(_ body: () -> Void) {
        let key = "syncEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }

    // MARK: - T-1797: allocator never reaches the counter store

    @Test
    func allocateNextID_withCloudSyncInactive_throwsWithoutTouchingCounterStore() async {
        let store = InMemoryCounterStore(initialNextDisplayID: 7)
        let allocator = DisplayIDAllocator(store: store, isCloudSyncActive: false)

        await #expect(throws: DisplayIDAllocator.Error.cloudSyncInactive) {
            try await allocator.allocateNextID()
        }

        let untouched = await store.wasNeverAccessed
        #expect(untouched, "Counter store must not be read or written while iCloud Sync is off")
    }

    @Test
    func allocateNextID_withCloudSyncActive_stillAllocates() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 7)
        let allocator = DisplayIDAllocator(store: store, isCloudSyncActive: true)

        let id = try await allocator.allocateNextID()
        #expect(id == 7)
    }

    @Test
    func promoteProvisionalTasks_withCloudSyncInactive_leavesTasksProvisional() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, isCloudSyncActive: false)

        let task = TransitTask(name: "Offline", type: .feature, project: project, displayID: .provisional)
        context.insert(task)
        try context.save()

        await allocator.promoteProvisionalTasks(in: context)

        #expect(task.permanentDisplayId == nil, "Provisional IDs must accumulate while sync is disabled")
        let untouched = await store.wasNeverAccessed
        #expect(untouched, "Scene/connectivity promotion must not reach the CloudKit counter")
    }

    @Test
    func promoteProvisionalMilestones_withCloudSyncInactive_leavesMilestonesProvisional() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, isCloudSyncActive: false)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let milestone = Milestone(name: "Offline", description: nil, project: project, displayID: .provisional)
        context.insert(milestone)
        try context.save()

        await service.promoteProvisionalMilestones()

        #expect(milestone.permanentDisplayId == nil)
        let untouched = await store.wasNeverAccessed
        #expect(untouched, "Milestone promotion must not reach the CloudKit counter")
    }

    // MARK: - T-1797: creation paths fall back to provisional IDs

    @Test
    func createTask_withCloudSyncInactive_assignsProvisionalID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, isCloudSyncActive: false)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)

        let task = try await service.createTask(
            name: "New", description: nil, type: .feature, project: project
        )

        #expect(task.permanentDisplayId == nil, "Task created while sync is off must keep a provisional ID")
        let untouched = await store.wasNeverAccessed
        #expect(untouched, "Task creation must not read or write the CloudKit counter while sync is off")
    }

    @Test
    func createMilestone_withCloudSyncInactive_assignsProvisionalID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, isCloudSyncActive: false)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let milestone = try await service.createMilestone(
            name: "New", description: nil, project: project
        )

        #expect(milestone.permanentDisplayId == nil)
        let untouched = await store.wasNeverAccessed
        #expect(untouched, "Milestone creation must not read or write the CloudKit counter while sync is off")
    }

    // MARK: - T-1797: maintenance counter-advance fence

    @Test
    func reassignDuplicates_withCloudSyncInactive_neverTouchesCounterStore() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let taskStore = InMemoryCounterStore(initialNextDisplayID: 1)
        let milestoneStore = InMemoryCounterStore(initialNextDisplayID: 1)
        let service = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: DisplayIDAllocator(store: taskStore, isCloudSyncActive: false),
            milestoneAllocator: DisplayIDAllocator(store: milestoneStore, isCloudSyncActive: false),
            commentService: CommentService(modelContext: context)
        )

        for name in ["A", "B"] {
            let task = TransitTask(name: name, type: .feature, project: project, displayID: .permanent(5))
            context.insert(task)
        }
        try context.save()

        let result = await service.reassignDuplicates()

        let taskUntouched = await taskStore.wasNeverAccessed
        let milestoneUntouched = await milestoneStore.wasNeverAccessed
        #expect(taskUntouched, "Counter-advance fence must not reach CloudKit while sync is off")
        #expect(milestoneUntouched)
        #expect(result.groups.first?.failure?.code == .counterAdvanceFailed)
        #expect(result.groups.first?.reassignments.isEmpty == true)
    }

    // MARK: - T-1857: preference vs. active mode

    @Test
    func makeModelConfiguration_recordsTheModeTheContainerWasBuiltWith() {
        withSavedDefaults {
            UserDefaults.standard.set(false, forKey: "syncEnabled")
            let manager = SyncManager()
            let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self])

            _ = manager.makeModelConfiguration(schema: schema)

            #expect(manager.isCloudSyncActive == false)
            #expect(manager.syncChangeRequiresRestart == false)
        }
    }

    @Test
    func setSyncEnabled_doesNotChangeTheActiveMode_andFlagsRestartRequired() {
        withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let manager = SyncManager()
            let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self])
            _ = manager.makeModelConfiguration(schema: schema)
            #expect(manager.isCloudSyncActive == true)

            manager.setSyncEnabled(false)

            #expect(manager.isSyncEnabled == false, "Preference flips immediately")
            #expect(manager.isCloudSyncActive == true, "The live container is still CloudKit-backed until relaunch")
            #expect(manager.syncChangeRequiresRestart, "Settings must disclose that a relaunch is required")

            manager.setSyncEnabled(true)
            #expect(manager.syncChangeRequiresRestart == false, "Reverting the toggle clears the restart notice")
        }
    }

    @Test
    func settingsFootnote_alwaysStatesRestartScope_andEscalatesWhenPending() {
        let steady = SettingsView.syncFootnote(requiresRestart: false)
        let pending = SettingsView.syncFootnote(requiresRestart: true)

        // The toggle must never read as taking effect immediately (T-1857).
        #expect(steady.contains("quit and reopen"))
        #expect(pending.contains("Quit and reopen"))
        #expect(pending.contains("syncing continues as it was when Transit launched"))
        #expect(steady != pending)
    }

    @Test
    func recordActiveCloudSync_overridesTheInferredMode() {
        withSavedDefaults {
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            let manager = SyncManager()

            // Test/UI-test hosts build an in-memory, CloudKit-free container without
            // going through makeModelConfiguration.
            manager.recordActiveCloudSync(false)

            #expect(manager.isCloudSyncActive == false)
            #expect(manager.syncChangeRequiresRestart)
        }
    }
}
