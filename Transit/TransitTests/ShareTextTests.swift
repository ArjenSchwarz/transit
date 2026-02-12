import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ShareTextTests {

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    private func makeProject(in context: ModelContext, name: String = "My Project") -> Project {
        let project = Project(name: name, description: "", gitRepo: nil, colorHex: "#0000FF")
        context.insert(project)
        return project
    }

    // MARK: - Header

    @Test func shareTextIncludesDisplayIDNameAndType() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Fix login", type: .bug, project: project, displayID: .permanent(42))
        context.insert(task)

        let text = task.shareText
        #expect(text.hasPrefix("# T-42 Fix login (Bug)\n"))
    }

    @Test func shareTextUsesProvisionalDisplayID() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Research caching", type: .research, project: project, displayID: .provisional)
        context.insert(task)

        let text = task.shareText
        #expect(text.hasPrefix("# T-\u{2022} Research caching (Research)\n"))
    }

    // MARK: - Project

    @Test func shareTextIncludesProjectName() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "Transit")
        let task = TransitTask(name: "Add share", type: .feature, project: project, displayID: .permanent(1))
        context.insert(task)

        #expect(task.shareText.contains("Project: Transit\n"))
    }

    // MARK: - Description

    @Test func shareTextIncludesDescription() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(
            name: "Task",
            description: "Detailed description here",
            type: .feature,
            project: project,
            displayID: .permanent(1)
        )
        context.insert(task)

        #expect(task.shareText.contains("\nDetailed description here\n"))
    }

    @Test func shareTextOmitsEmptyDescription() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Task", description: nil, type: .chore, project: project, displayID: .permanent(1))
        context.insert(task)

        // Should only have header and project line, no blank line for description
        #expect(!task.shareText.contains("\n\n"))
    }

    // MARK: - Metadata

    @Test func shareTextIncludesMetadataSortedByKey() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(
            name: "Task",
            type: .feature,
            project: project,
            displayID: .permanent(1),
            metadata: ["git.branch": "main", "agent.model": "claude"]
        )
        context.insert(task)

        let text = task.shareText
        #expect(text.contains("agent.model: claude\n"))
        #expect(text.contains("git.branch: main\n"))

        // agent.model should come before git.branch (alphabetical)
        let agentPos = text.range(of: "agent.model")!.lowerBound
        let gitPos = text.range(of: "git.branch")!.lowerBound
        #expect(agentPos < gitPos)
    }

    @Test func shareTextOmitsMetadataWhenEmpty() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        context.insert(task)

        let text = task.shareText
        // No trailing blank line for metadata section
        #expect(text.hasSuffix("Project: My Project\n"))
    }

    // MARK: - Full format

    @Test func shareTextFullFormat() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "Transit")
        let task = TransitTask(
            name: "Add share button",
            description: "Allow copying task details from the detail view",
            type: .feature,
            project: project,
            displayID: .permanent(41),
            metadata: ["git.branch": "T-41/share"]
        )
        context.insert(task)

        let expected = """
            # T-41 Add share button (Feature)
            Project: Transit

            Allow copying task details from the detail view

            git.branch: T-41/share\n
            """
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .init(charactersIn: " ")) }
            .joined(separator: "\n")

        #expect(task.shareText == expected)
    }
}
