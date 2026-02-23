import Foundation
import Testing
@testable import Transit

// MARK: - ReportMarkdownFormatter Milestone Tests

@MainActor
@Suite("ReportMarkdownFormatter Milestones")
struct ReportMarkdownFormatterMilestoneTests {

    @Test("Markdown includes milestones section when milestones present")
    func markdownIncludesMilestonesSection() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Alpha",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-1", name: "Task",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 1,
                            milestoneName: nil
                        )
                    ],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-1", name: "v1.0",
                            isAbandoned: false, taskCount: 3
                        )
                    ]
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("### Milestones"))
        #expect(output.contains("- M-1: v1.0 (3 tasks)"))
    }

    @Test("Markdown omits milestones section when no milestones")
    func markdownOmitsMilestonesSection() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Alpha",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-1", name: "Task",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 1,
                            milestoneName: nil
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(!output.contains("### Milestones"))
    }

    @Test("Abandoned milestone rendered with strikethrough")
    func abandonedMilestoneStrikethrough() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-2", name: "Dropped",
                            isAbandoned: true, taskCount: 1
                        )
                    ]
                )
            ],
            totalDone: 0,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- ~~M-2: Dropped~~ (Abandoned, 1 task)"))
    }

    @Test("Milestone with 1 task uses singular form")
    func milestoneSingularTask() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-1", name: "Solo",
                            isAbandoned: false, taskCount: 1
                        )
                    ]
                )
            ],
            totalDone: 0,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- M-1: Solo (1 task)"))
    }

    @Test("Task line includes milestone name suffix")
    func taskMilestoneNameSuffix() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-5", name: "Add login",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 5,
                            milestoneName: "v1.0"
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- T-5: Feature: Add login [v1.0]"))
    }

    @Test("Task line without milestone has no suffix")
    func taskNoMilestoneSuffix() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-5", name: "Add login",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 5,
                            milestoneName: nil
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- T-5: Feature: Add login"))
        #expect(!output.contains("["))
    }

    @Test("Abandoned task with milestone shows both markers")
    func abandonedTaskWithMilestone() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-3", name: "Old feature",
                            taskType: .feature, isAbandoned: true,
                            completionDate: .now, permanentDisplayId: 3,
                            milestoneName: "v1.0"
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 0,
            totalAbandoned: 1
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- ~~T-3: Feature: Old feature~~ (Abandoned) [v1.0]"))
    }
}
