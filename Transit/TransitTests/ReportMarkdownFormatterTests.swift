import Foundation
import Testing
@testable import Transit

// MARK: - Test Helpers

@MainActor
private func makeReportData(
    dateRangeLabel: String = "This Week",
    groups: [ProjectGroup] = [],
    totalDone: Int? = nil,
    totalAbandoned: Int? = nil
) -> ReportData {
    let done = totalDone ?? groups.flatMap(\.tasks).filter { !$0.isAbandoned }.count
    let abandoned = totalAbandoned ?? groups.flatMap(\.tasks).filter(\.isAbandoned).count
    return ReportData(
        dateRangeLabel: dateRangeLabel,
        projectGroups: groups,
        totalDone: done,
        totalAbandoned: abandoned
    )
}

@MainActor
private func makeGroup(
    name: String,
    tasks: [ReportTask]
) -> ProjectGroup {
    ProjectGroup(id: UUID(), projectName: name, tasks: tasks)
}

@MainActor
private func makeTask(
    displayID: String = "T-1",
    name: String = "Task",
    taskType: TaskType = .feature,
    isAbandoned: Bool = false,
    completionDate: Date = .now,
    permanentDisplayId: Int? = 1
) -> ReportTask {
    ReportTask(
        id: UUID(),
        displayID: displayID,
        name: name,
        taskType: taskType,
        isAbandoned: isAbandoned,
        completionDate: completionDate,
        permanentDisplayId: permanentDisplayId
    )
}

// MARK: - Template Structure Tests

@MainActor
@Suite("ReportMarkdownFormatter")
struct ReportMarkdownFormatterTests {

    @Test("Output matches template structure with title, summary, project sections")
    func fullTemplateStructure() {
        let data = makeReportData(
            dateRangeLabel: "This Week",
            groups: [
                makeGroup(name: "Alpha", tasks: [
                    makeTask(displayID: "T-42", name: "Implement login"),
                    makeTask(displayID: "T-5", name: "Old feature", isAbandoned: true)
                ]),
                makeGroup(name: "Beta", tasks: [
                    makeTask(displayID: "T-17", name: "Fix dashboard layout")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)

        #expect(output.contains("# Report: This Week"))
        #expect(output.contains("**3 tasks**"))
        #expect(output.contains("## Alpha"))
        #expect(output.contains("## Beta"))
        #expect(output.contains("- T-42: Feature: Implement login"))
        #expect(output.contains("- ~~T-5: Feature: Old feature~~ (Abandoned)"))
        #expect(output.contains("- T-17: Feature: Fix dashboard layout"))
    }

    @Test("Title includes date range label")
    func titleIncludesDateRangeLabel() {
        let data = makeReportData(dateRangeLabel: "Last Month")
        let output = ReportMarkdownFormatter.format(data)
        #expect(output.hasPrefix("# Report: Last Month\n"))
    }

    @Test("Summary counts show total, done, and abandoned")
    func summaryCounts() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(name: "Done1"),
                    makeTask(name: "Done2"),
                    makeTask(name: "Abandoned1", isAbandoned: true)
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("**3 tasks** (2 done, 1 abandoned)"))
    }

    @Test("Summary with only done tasks omits abandoned count")
    func summaryOnlyDone() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(name: "Done1"),
                    makeTask(name: "Done2")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("**2 tasks** (2 done)"))
    }

    @Test("Summary with only abandoned tasks omits done count")
    func summaryOnlyAbandoned() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(name: "Abn1", isAbandoned: true)
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("**1 task** (1 abandoned)"))
    }

    @Test("Per-project summary shows both counts when non-zero")
    func perProjectSummaryBothCounts() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(name: "Done1"),
                    makeTask(name: "Done2"),
                    makeTask(name: "Done3"),
                    makeTask(name: "Abn1", isAbandoned: true)
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        let lines = output.components(separatedBy: "\n")
        // Line after "## Project" should be the summary
        guard let projectIndex = lines.firstIndex(of: "## Project") else {
            Issue.record("Missing '## Project' heading")
            return
        }
        let summaryIndex = projectIndex + 2  // blank line + summary
        #expect(lines[summaryIndex] == "3 done, 1 abandoned")
    }

    @Test("Per-project summary omits zero abandoned count")
    func perProjectSummaryOnlyDone() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(name: "Done1"),
                    makeTask(name: "Done2")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        let lines = output.components(separatedBy: "\n")
        guard let projectIndex = lines.firstIndex(of: "## Project") else {
            Issue.record("Missing '## Project' heading")
            return
        }
        let summaryIndex = projectIndex + 2
        #expect(lines[summaryIndex] == "2 done")
    }

    @Test("Per-project summary omits zero done count")
    func perProjectSummaryOnlyAbandoned() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(name: "Abn1", isAbandoned: true),
                    makeTask(name: "Abn2", isAbandoned: true)
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        let lines = output.components(separatedBy: "\n")
        guard let projectIndex = lines.firstIndex(of: "## Project") else {
            Issue.record("Missing '## Project' heading")
            return
        }
        let summaryIndex = projectIndex + 2
        #expect(lines[summaryIndex] == "2 abandoned")
    }

    @Test("Abandoned tasks rendered with strikethrough and (Abandoned)")
    func abandonedTaskStrikethrough() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(displayID: "T-5", name: "Old feature", isAbandoned: true)
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- ~~T-5: Feature: Old feature~~ (Abandoned)"))
    }

    @Test("Normal tasks rendered without strikethrough")
    func normalTaskNoStrikethrough() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(displayID: "T-42", name: "Implement login")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- T-42: Feature: Implement login"))
        #expect(!output.contains("~~"))
        #expect(!output.contains("(Abandoned)"))
    }

    @Test("GFM metacharacters escaped in task names")
    func gfmEscapingTaskNames() {
        let specialName = #"back\ tick` star* under_ tilde~ [bracket] #hash <angle> |pipe"#
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(displayID: "T-1", name: specialName)
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains(#"back\\ tick\`"#))
        #expect(output.contains(#"star\*"#))
        #expect(output.contains(#"under\_"#))
        #expect(output.contains(#"tilde\~"#))
        #expect(output.contains(#"\[bracket\]"#))
        #expect(output.contains(##"\#hash"##))
        #expect(output.contains(#"\<angle\>"#))
        #expect(output.contains(#"\|pipe"#))
    }

    @Test("GFM metacharacters escaped in project names")
    func gfmEscapingProjectNames() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project *bold*", tasks: [
                    makeTask(name: "Task")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains(#"## Project \*bold\*"#))
    }

    @Test("Newlines in task names normalized to spaces")
    func newlinesInTaskNamesNormalized() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "Project", tasks: [
                    makeTask(displayID: "T-1", name: "Line one\nLine two\rLine three")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("T-1: Feature: Line one Line two Line three"))
    }

    @Test("Newlines in project names normalized to spaces")
    func newlinesInProjectNamesNormalized() {
        let data = makeReportData(
            groups: [
                makeGroup(name: "My\nProject", tasks: [
                    makeTask(name: "Task")
                ])
            ]
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("## My Project"))
    }

    @Test("Empty state shows correct message")
    func emptyState() {
        let data = makeReportData(dateRangeLabel: "This Week")

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("# Report: This Week"))
        #expect(output.contains("No tasks completed or abandoned in this period."))
        #expect(!output.contains("## "))
        #expect(!output.contains("**"))
    }
}
