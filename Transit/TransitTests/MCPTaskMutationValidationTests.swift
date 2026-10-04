#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPTaskMutationValidationTests {
    @Test(arguments: [" text ", "\ntext\t", "e\u{301}"])
    func pureCommentNormalization(content: String) throws {
        let normalized = try CommentInputValidation.normalize(content: content, authorName: " Agent \n")
        #expect(normalized.content.utf8.elementsEqual(content.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        #expect(normalized.authorName == "Agent")
    }

    @Test(arguments: ["content", "author", "both"])
    func pureCommentErrorsRemainDistinct(field: String) {
        do {
            _ = try CommentInputValidation.normalize(content: field == "author" ? "text" : " \n",
                                                       authorName: field == "content" ? "agent" : " \t")
            Issue.record("Blank comment inputs must reject")
        } catch let error as CommentInputValidation.Error {
            #expect(error == (field == "author" ? .emptyAuthorName : .emptyContent))
        } catch { Issue.record("Unexpected comment validation error: \(error)") }
    }

    @Test(arguments: ["same", "done", "abandoned", "leaveTerminal", "terminalToTerminal", "nonterminal"])
    func symbolicStatusTimestampEffects(scenario: String) throws {
        let current: String
        let target: String
        switch scenario {
        case "same": (current, target) = ("idea", "idea")
        case "done": (current, target) = ("idea", "done")
        case "abandoned": (current, target) = ("idea", "abandoned")
        case "leaveTerminal": (current, target) = ("done", "idea")
        case "terminalToTerminal": (current, target) = ("done", "abandoned")
        default: (current, target) = ("idea", "planning")
        }
        let value = try MCPTaskMutationValidation.status(currentStatus: current, targetStatus: target,
                                                        comment: nil, authorName: nil)
        #expect(value.targetStatus == target)
        #expect(value.statusChanged == (current != target))
        #expect(value.comment == nil)
        #expect(value.lastStatusChange == (current == target ? .unchanged : .update))
        let expected: MCPTaskMutationValidation.TimestampAction
        switch scenario {
        case "done", "abandoned", "terminalToTerminal": expected = .set
        case "leaveTerminal": expected = .clear
        default: expected = .unchanged
        }
        #expect(value.completion == expected)
    }

    @Test(arguments: ["absent", "blank", "content"])
    func sameStatusCommentSemantics(scenario: String) throws {
        let comment: String?
        switch scenario {
        case "absent": comment = nil
        case "blank": comment = " \n"
        default: comment = " Reason \n"
        }
        let value = try MCPTaskMutationValidation.status(currentStatus: "idea", targetStatus: "idea",
                                                        comment: comment, authorName: " Agent ")
        #expect(!value.statusChanged && value.lastStatusChange == .unchanged && value.completion == .unchanged)
        #expect(value.comment?.content == (scenario == "content" ? "Reason" : nil))
        #expect(value.comment?.authorName == (scenario == "content" ? "Agent" : nil))
    }

    @Test(arguments: ["invalidStatus", "blankCommentMissingAuthor", "blankCommentBlankAuthor", "contentMissingAuthor"])
    func protectedStatusValidationOrder(scenario: String) {
        let status = scenario == "invalidStatus" ? "unsupported" : "idea"
        let content = scenario == "contentMissingAuthor" ? "reason" : " \n"
        do {
            _ = try MCPTaskMutationValidation.status(currentStatus: "idea", targetStatus: status,
                comment: content, authorName: scenario == "blankCommentBlankAuthor" ? " \t" : nil)
            Issue.record("Protected status input must reject")
        } catch let error as MCPWriteFailure {
            #expect(error.code == (scenario == "invalidStatus" ? "INVALID_STATUS" : "INVALID_INPUT"))
        } catch { Issue.record("Unexpected protected validation error: \(error)") }
    }

    @Test
    func absentCommentIgnoresUnusedBlankAuthor() throws {
        let value = try MCPTaskMutationValidation.status(currentStatus: "idea", targetStatus: "idea",
                                                        comment: nil, authorName: " \n")
        #expect(value.comment == nil && !value.statusChanged)
    }
}

/// Existing-service controls run independently of the new RED placeholders.
@MainActor @Suite(.serialized)
struct MCPTaskMutationBaselineTests {
    @Test(arguments: ["invalidFirst", "blankMissingAuthor", "blankValidAuthor", "absentComment"])
    func existingProtectedStatusContract(scenario: String) throws {
        let fixture = try MCPBatchTaskPreviewFixture()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false)
        var saves = 0
        let services = MCPWriteCommandServices(
            tasks: TaskService(modelContext: fixture.owner.context, displayIDAllocator: allocator,
                statusSave: { _ in saves += 1; throw MCPBatchTaskPreviewFixture.Fault.injected }),
            projects: ProjectService(modelContext: fixture.owner.context),
            comments: CommentService(modelContext: fixture.owner.context),
            milestones: MilestoneService(modelContext: fixture.owner.context, displayIDAllocator: allocator),
            context: fixture.owner.context)
        var arguments: [String: Any] = ["taskId": fixture.targets[0].id.uuidString,
            "idempotencyKey": "baseline", "expectedRevision": try fixture.revision(),
            "status": scenario == "invalidFirst" ? "unsupported" : "idea"]
        if scenario != "absentComment" { arguments["comment"] = " \n" }
        if scenario == "blankValidAuthor" { arguments["authorName"] = " Agent " }
        do {
            let command = try MCPWriteCommand.validate(tool: "update_task_status", arguments: arguments)
            let result = try command.apply(.task(fixture.targets[0].id), using: services)
            #expect(scenario == "blankValidAuthor" || scenario == "absentComment")
            #expect(result["comment"] is NSNull)
        } catch let error as MCPWriteFailure {
            #expect(error.code == (scenario == "invalidFirst" ? "INVALID_STATUS" : "INVALID_INPUT"))
            #expect(scenario == "invalidFirst" || scenario == "blankMissingAuthor")
        }
        #expect(saves == 0 && !fixture.owner.context.hasChanges)
        try fixture.assertUntouched()
    }

    @Test(arguments: ["trim", "blankContent", "blankAuthor"])
    func existingCommentServiceContract(scenario: String) throws {
        let fixture = try MCPBatchTaskPreviewFixture()
        let service = CommentService(modelContext: fixture.owner.context)
        do {
            let comment = try service.addComment(to: fixture.targets[0],
                content: scenario == "blankContent" ? " \n" : " Reason ",
                authorName: scenario == "blankAuthor" ? " \t" : " Agent ", isAgent: true, save: nil)
            #expect(scenario == "trim")
            #expect(comment.content == "Reason" && comment.authorName == "Agent" && comment.isAgent)
        } catch let error as CommentService.Error {
            #expect(error == (scenario == "blankContent" ? .emptyContent : .emptyAuthorName))
            #expect(scenario != "trim")
        }
    }

    @Test(arguments: ["same", "terminal", "leaveTerminal", "nonterminalPreservesMalformedCompletion"])
    func existingStatusServiceContract(scenario: String) throws {
        let fixture = try MCPBatchTaskPreviewFixture()
        let task = fixture.targets[0]
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        task.lastStatusChangeDate = fixed
        task.completionDate = fixed
        if scenario == "leaveTerminal" { task.status = .done }
        let target: TaskStatus = scenario == "terminal" ? .done : (scenario == "same" ? .idea : .planning)
        let service = TaskService(modelContext: fixture.owner.context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false))
        let comment = try service.updateStatus(task: task, to: target, comment: " \n",
            commentAuthor: nil, commentService: CommentService(modelContext: fixture.owner.context), save: false)
        #expect(comment == nil)
        #expect(task.status == target)
        #expect((task.lastStatusChangeDate == fixed) == (scenario == "same"))
        if scenario == "leaveTerminal" { #expect(task.completionDate == nil) }
        if scenario == "terminal" { #expect(task.completionDate != nil && task.completionDate != fixed) }
        if scenario == "same" || scenario == "nonterminalPreservesMalformedCompletion" {
            #expect(task.completionDate == fixed)
        }
    }

    @Test(arguments: ["trim", "clear", "clearMilestone", "displayPrecedence"])
    // Each row checks a distinct existing validator result without applying it.
    // swiftlint:disable:next cyclomatic_complexity
    func existingUpdateValidatorIsReadOnly(scenario: String) throws {
        let fixture = try MCPBatchTaskPreviewFixture()
        let service = MilestoneService(modelContext: fixture.owner.context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(), isCloudSyncActive: false))
        let args: [String: Any]
        switch scenario {
        case "trim": args = ["name": " Name ", "description": " Description "]
        case "clear": args = ["description": " \n", "metadata": [:] as [String: String]]
        case "clearMilestone": args = ["clearMilestone": true, "milestoneDisplayId": 999, "milestone": "Missing"]
        default: args = ["milestoneDisplayId": 9, "milestone": "Missing"]
        }
        let update = try TaskUpdateValidator.validate(args, task: fixture.targets[0], milestoneService: service).get()
        if scenario == "trim" {
            #expect(update.name == "Name")
            if case .set(let text) = update.description {
                #expect(text == "Description")
            } else { Issue.record("Description must trim") }
        }
        if scenario == "clear" {
            if case .clear = update.description {} else { Issue.record("Description must clear") }
            if case .clear = update.metadata {} else { Issue.record("Metadata must clear") }
        }
        if scenario == "clearMilestone" {
            if case .clear? = update.milestoneAction {} else { Issue.record("Clear takes precedence") }
        }
        if scenario == "displayPrecedence" {
            if case .assign(let milestone)? = update.milestoneAction {
                #expect(milestone.id == fixture.milestone.id)
            } else { Issue.record("Display ID takes precedence") }
        }
        #expect(!fixture.owner.context.hasChanges)
        try fixture.assertUntouched()
    }
}
#endif
