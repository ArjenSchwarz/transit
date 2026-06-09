import Foundation
import SwiftData
import Testing
@testable import Transit

/// Cross-surface regression test for the effective-priority invariant (Req 1.4).
///
/// A legacy/pre-feature task — one whose `priorityRawValue` is the empty string
/// `""` — has no stored priority. The computed `task.priority` accessor must
/// resolve it to `.medium`, and EVERY read surface (display, filter predicate,
/// serialization) must go through that accessor rather than reading
/// `priorityRawValue` directly. This single test guards all five read surfaces
/// at once, so a raw-value copy-paste (the one way to silently break Req 1.4 on
/// a single surface) fails here:
///
///   1. Board — `DashboardLogic.buildFilteredColumns` / `matchesFilters`
///   2. MCP query filter — `MCPQueryFilters.matches`
///   3. MCP serialization — `IntentHelpers.taskToDict`
///   4. Intent query filter — `QueryTasksIntent` `applyFilters` (via `execute`)
///   5. Intent update response — `IntentHelpers.taskUpdateResponseDict`
@MainActor @Suite(.serialized)
struct EffectivePriorityInvariantTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let project: ProjectService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    /// Creates a legacy task: a normal task whose stored priority is then forced
    /// to the empty string. We set `priorityRawValue` directly (NOT the `priority`
    /// setter, which would write `"medium"`) because the empty raw value is the
    /// whole point of the regression.
    @discardableResult
    private func makeLegacyTask(
        in context: ModelContext, project: Project, displayId: Int = 1
    ) -> TransitTask {
        let task = TransitTask(name: "Legacy", type: .feature, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        task.priorityRawValue = ""
        context.insert(task)
        return task
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    // MARK: - Accessor (the invariant's source of truth)

    /// Sanity check: the computed accessor resolves an empty raw value to medium.
    @Test func legacyTaskReadsAsMediumThroughAccessor() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let legacy = makeLegacyTask(in: svc.context, project: project)

        #expect(legacy.priorityRawValue == "")
        #expect(legacy.priority == .medium)
    }

    // MARK: - Surface 1: Board filter (DashboardLogic.matchesFilters)

    @Test func boardMediumFilterIncludesLegacyTask() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let legacy = makeLegacyTask(in: svc.context, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [legacy],
            selectedProjectIDs: [],
            selectedPriorities: [.medium],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks.first?.name == "Legacy")
    }

    // MARK: - Surface 3: MCP serialization (IntentHelpers.taskToDict)

    @Test func taskToDictSerializesLegacyAsMedium() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let legacy = makeLegacyTask(in: svc.context, project: project)

        let dict = IntentHelpers.taskToDict(legacy, formatter: ISO8601DateFormatter())

        #expect(dict["priority"] as? String == "medium")
    }

    // MARK: - Surface 4: Intent query filter (QueryTasksIntent.applyFilters)

    @Test func intentMediumFilterIncludesLegacyTask() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeLegacyTask(in: svc.context, project: project)

        let result = QueryTasksIntent.execute(
            input: "{\"priority\":\"medium\"}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "Legacy")
        #expect(parsed.first?["priority"] as? String == "medium")
    }

    // MARK: - Surface 5: Intent update response (IntentHelpers.taskUpdateResponseDict)

    @Test func taskUpdateResponseDictSerializesLegacyAsMedium() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let legacy = makeLegacyTask(in: svc.context, project: project)

        let dict = IntentHelpers.taskUpdateResponseDict(legacy)

        #expect(dict["priority"] as? String == "medium")
    }

    // MARK: - Surface 2: MCP query filter (MCPQueryFilters.matches) — macOS only

    #if os(macOS)
    @Test func mcpMediumFilterIncludesLegacyTask() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let legacy = makeLegacyTask(in: svc.context, project: project)

        let filters = MCPQueryFilters.from(
            args: ["priority": "medium"], type: nil, projectId: nil
        )

        #expect(filters.matches(legacy))
    }
    #endif
}
