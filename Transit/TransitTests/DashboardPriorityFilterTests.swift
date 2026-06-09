import Foundation
import Testing
@testable import Transit

/// Dashboard priority-filter predicate tests. Kept separate from
/// `DashboardFilterTests` so neither file exceeds SwiftLint's length limits.
@MainActor
struct DashboardPriorityFilterTests {

    // MARK: - Helpers

    private func makeProject(name: String = "Test", colorHex: String = "FF0000") -> Project {
        Project(name: name, description: "Description", gitRepo: nil, colorHex: colorHex)
    }

    private func makeTask(
        name: String = "Task",
        type: TaskType = .feature,
        priority: TaskPriority = .medium,
        project: Project
    ) -> TransitTask {
        let task = TransitTask(name: name, type: type, project: project, displayID: .provisional)
        task.statusRawValue = TaskStatus.idea.rawValue
        task.priority = priority
        return task
    }

    // MARK: - Priority filter [req 3.2, 3.3, 3.4]

    @Test func priorityFilterReducesToSelectedPriorities() {
        let project = makeProject()
        let lowTask = makeTask(name: "Low", priority: .low, project: project)
        let mediumTask = makeTask(name: "Medium", priority: .medium, project: project)
        let highTask = makeTask(name: "High", priority: .high, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [lowTask, mediumTask, highTask],
            selectedProjectIDs: [],
            selectedPriorities: [.high],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "High")
    }

    @Test func priorityFilterWithMultiplePrioritiesReturnsAllMatching() {
        let project = makeProject()
        let lowTask = makeTask(name: "Low", priority: .low, project: project)
        let mediumTask = makeTask(name: "Medium", priority: .medium, project: project)
        let highTask = makeTask(name: "High", priority: .high, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [lowTask, mediumTask, highTask],
            selectedProjectIDs: [],
            selectedPriorities: [.high, .low],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 2)
        let names = Set(ideaTasks.map(\.name))
        #expect(names == ["High", "Low"])
    }

    @Test func emptyPriorityFilterShowsAllPriorities() {
        let project = makeProject()
        let lowTask = makeTask(name: "Low", priority: .low, project: project)
        let mediumTask = makeTask(name: "Medium", priority: .medium, project: project)
        let highTask = makeTask(name: "High", priority: .high, project: project)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [lowTask, mediumTask, highTask],
            selectedProjectIDs: [],
            selectedPriorities: [],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 3)
    }

    /// A task with no stored priority (legacy) reads as medium via the computed
    /// accessor, so a `[.medium]` filter must include it. [req 1.4, 3.2]
    @Test func priorityFilterUsesComputedAccessorForLegacyTasks() {
        let project = makeProject()
        let legacyTask = makeTask(name: "Legacy", project: project)
        legacyTask.priorityRawValue = ""

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [legacyTask],
            selectedProjectIDs: [],
            selectedPriorities: [.medium],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Legacy")
    }

    // MARK: - Intersection with project and type filters [req 3.4]

    @Test func combinedPriorityProjectAndTypeFilterReturnsIntersection() {
        let projectA = makeProject(name: "A")
        let projectB = makeProject(name: "B")
        let match = makeTask(name: "Match", type: .bug, priority: .high, project: projectA)
        let wrongPriority = makeTask(name: "WrongPriority", type: .bug, priority: .low, project: projectA)
        let wrongType = makeTask(name: "WrongType", type: .feature, priority: .high, project: projectA)
        let wrongProject = makeTask(name: "WrongProject", type: .bug, priority: .high, project: projectB)

        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: [match, wrongPriority, wrongType, wrongProject],
            selectedProjectIDs: [projectA.id],
            selectedTypes: [.bug],
            selectedPriorities: [.high],
            now: .now
        )

        let ideaTasks = columns[.idea] ?? []
        #expect(ideaTasks.count == 1)
        #expect(ideaTasks[0].name == "Match")
    }
}
