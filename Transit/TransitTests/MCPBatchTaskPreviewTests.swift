#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// One serialized table-driven suite keeps the owning disk fixture boundary visible.
// swiftlint:disable type_body_length
@MainActor @Suite(.serialized)
struct MCPBatchTaskPreviewTests {
    typealias Fixture = MCPBatchTaskPreviewFixture

    @Test(arguments: ["deleted", "inserted"])
    func pendingMilestoneDeletionAndInsertionUseSavedIdentity(scenario: String) throws {
        let fixture = try Fixture()
        let name = scenario == "deleted" ? "Saved deleted milestone" : "UI unsaved milestone insert"
        let item = try fixture.item(changes: ["milestone": name])
        fixture.makePending(autosave: false)
        defer { fixture.verifyPendingAfterReturn(autosave: false) }
        let report = try fixture.preview([item])
        if scenario == "deleted" {
            #expect(report.entries[0].state == .valid)
            #expect(Fixture.field("milestoneId", report.entries[0].proposedEffects)
                    == .string(fixture.deletedMilestone.id.uuidString))
        } else {
            #expect(report.entries[0].state == .invalid)
            #expect(report.entries[0].code == "MILESTONE_NOT_FOUND")
            #expect(report.entries[0].proposedEffects == nil)
        }
        #expect(fixture.milestoneReads > 0)
        try fixture.assertUntouched(autosave: false)
    }

    @Test
    func pendingInsertionIsMissingButPendingDeletionRemainsSaved() throws {
        let fixture = try Fixture()
        let deletionRevision = try MCPRecordSnapshot.task(fixture.deletion, in: fixture.owner.context).revision
        fixture.makePending(autosave: false)
        let inserted = try #require(fixture.pending)
        let items: [[String: Any]] = [
            ["itemId": "inserted", "operation": "add_comment", "arguments": [
                "taskId": inserted.id.uuidString, "idempotencyKey": "inserted",
                "content": "reason", "authorName": "agent"]],
            ["itemId": "deleted", "operation": "update_task", "arguments": [
                "taskId": fixture.deletion.id.uuidString, "idempotencyKey": "deleted",
                "expectedRevision": deletionRevision]]
        ]
        defer { fixture.verifyPendingAfterReturn(autosave: false) }
        let report = try fixture.preview(items)
        #expect(report.entries.map(\.state) == [.invalid, .valid])
        #expect(report.entries[0].code == "TASK_NOT_FOUND")
        #expect(Fixture.field("name", report.entries[1].current) == .string("Saved deletion"))
        try fixture.assertUntouched(autosave: false)
    }

    @Test(arguments: ["absent", "blank", "content", "invalid", "missingAuthor"])
    func integratedStatusValidationAndSymbolicEffects(scenario: String) throws {
        let fixture = try Fixture()
        var changes: [String: Any] = ["status": scenario == "invalid" ? "unsupported" : "idea"]
        if scenario != "absent" && scenario != "invalid" {
            changes["comment"] = scenario == "content" ? " Reason " : " \n"
            if scenario != "missingAuthor" { changes["authorName"] = " Agent " }
        }
        let report = try fixture.preview([fixture.item(operation: "update_task_status", changes: changes)])
        let entry = report.entries[0]
        if scenario == "invalid" || scenario == "missingAuthor" {
            #expect(entry.state == .invalid)
            #expect(entry.code == (scenario == "invalid" ? "INVALID_STATUS" : "INVALID_INPUT"))
            #expect(entry.proposedEffects == nil)
        } else {
            #expect(entry.state == .valid)
            let effects = try #require(entry.proposedEffects)
            #expect(Fixture.field("statusChanged", effects) == .boolean(false))
            #expect(Fixture.field("lastStatusChange", effects) == .string("unchanged"))
            #expect(Fixture.field("completion", effects) == .string("unchanged"))
            if scenario == "content" {
                let comment = Fixture.field("comment", effects)
                #expect(MCPBatchTaskRequestFixtures.field("content", in: comment) == .string("Reason"))
                #expect(MCPBatchTaskRequestFixtures.field("authorName", in: comment) == .string("Agent"))
            } else { #expect(Fixture.field("comment", effects) == .null) }
        }
        try fixture.assertUntouched()
    }

    @Test(arguments: [false, true])
    func pendingCommentsAndMilestonesNeverAffectSavedPreview(autosave: Bool) throws {
        let fixture = try Fixture()
        let revision = try fixture.revision()
        let item = try fixture.item(changes: ["milestone": "Saved milestone"])
        fixture.makePending(autosave: autosave)
        defer { fixture.verifyPendingAfterReturn(autosave: autosave) }
        let report = try fixture.preview([item])
        #expect(report.entries[0].state == .valid)
        #expect(Fixture.field("revision", report.entries[0].current) == .string(revision))
        #expect(Fixture.field("milestoneId", report.entries[0].proposedEffects)
                == .string(fixture.milestone.id.uuidString))
        #expect(fixture.milestoneReads > 0)
        guard case .array(let comments) = Fixture.field("comments", report.entries[0].current) else {
            Issue.record("Saved full comments required"); return
        }
        #expect(comments.count == 2)
        let texts = comments.compactMap { value -> String? in
            if case .string(let text) = MCPBatchTaskRequestFixtures.field("content", in: value) { return text }
            return nil
        }
        #expect(Set(texts) == ["Saved full comment", "Saved deleted comment"])
        let ids = comments.compactMap { value -> String? in
            if case .string(let id) = MCPBatchTaskRequestFixtures.field("id", in: value) { return id }
            return nil
        }
        #expect(Set(ids) == [fixture.comment.id.uuidString, fixture.deletedComment.id.uuidString])
        try fixture.assertUntouched(autosave: autosave)
    }

    @Test
    func emptyCommentReadFailureDoesNotInventEmptyObservation() throws {
        let fixture = try Fixture()
        fixture.failEveryCommentRead = true
        let report = try fixture.preview([fixture.item(1)], includeComments: false)
        #expect(report.entries[0].state == .unavailable)
        #expect(report.entries[0].current == nil && report.entries[0].proposedEffects == nil)
        #expect(fixture.commentReads == 1)
        try fixture.assertUntouched()
    }

    @Test(arguments: [false, true])
    func savedOnlyPreservesDirtyUI(autosave: Bool) throws {
        let fixture = try Fixture()
        let item = try fixture.item(changes: ["name": " Proposed "])
        fixture.makePending(autosave: autosave)
        defer { fixture.verifyPendingAfterReturn(autosave: autosave) }
        let report = try fixture.preview([item])
        #expect(report.entries.count == 1)
        #expect(report.entries[0].state == .valid)
        #expect(Fixture.field("name", report.entries[0].current) == .string("Saved 1"))
        #expect(Fixture.field("name", report.entries[0].proposedEffects) == .string("Proposed"))
        #expect(report.observation == "saved_local_store")
        #expect(report.keyState == "unchecked")
        #expect(report.advisory)
        #expect(report.isError == nil)
        #expect(fixture.taskReads == 1 && fixture.commentReads == 1)
        try fixture.assertUntouched(autosave: autosave)
    }

    @Test(arguments: [false, true])
    func failedReadPreservesDirtyUI(autosave: Bool) throws {
        let fixture = try Fixture()
        let item = try fixture.item()
        fixture.taskFault = fixture.targets[0].id
        fixture.makePending(autosave: autosave)
        defer { fixture.verifyPendingAfterReturn(autosave: autosave) }
        let report = try fixture.preview([item])
        #expect(report.entries[0].state == .unavailable)
        #expect(report.entries[0].current == nil)
        #expect(report.entries[0].proposedEffects == nil)
        #expect(report.isError == true)
        try fixture.assertUntouched(autosave: autosave)
    }

    @Test(arguments: [0, 1, 2])
    func UUIDCardinality(matches: Int) throws {
        let fixture = try Fixture()
        fixture.forcedMatches = matches
        let report = try fixture.preview([fixture.item()])
        let entry = report.entries[0]
        #expect(entry.state == (matches == 1 ? .valid : .invalid))
        if matches == 0 { #expect(entry.code == "TASK_NOT_FOUND") }
        if matches == 2 { #expect(entry.code == "DUPLICATE_TASK_IDENTIFIER") }
        #expect(fixture.commentReads == (matches == 1 ? 1 : 0))
        try fixture.assertUntouched()
    }

    @Test
    func mixedPreviewVisitsEveryItem() throws {
        let fixture = try Fixture()
        fixture.commentFault = fixture.targets[2].id
        // A required comment read must fail even when that task has no comments.
        let originalReads = fixture.reads()
        var reads = originalReads
        var commentCalls = 0
        reads.comments = { descriptor, context in
            commentCalls += 1
            if commentCalls == 3 {
                fixture.observe(context, pending: descriptor.includePendingChanges)
                throw Fixture.Fault.injected
            }
            return try originalReads.comments(descriptor, context)
        }
        let request = try fixture.request([
            fixture.item(0, changes: ["name": " Valid "]),
            fixture.item(1, changes: ["priority": "unsupported"]),
            fixture.item(2, operation: "add_comment")
        ])
        let report = try MCPBatchTaskPreview.evaluate(request, container: fixture.owner.container,
            persistence: PersistenceAvailability(), reads: reads)
        #expect(report.entries.map(\.index) == [0, 1, 2])
        #expect(report.entries.map(\.itemId) == ["original.0", "original.1", "original.2"])
        #expect(report.entries.map(\.state) == [.valid, .invalid, .unavailable])
        #expect(report.entries[1].code == "INVALID_PRIORITY")
        #expect(report.entries[2].proposedEffects == nil)
        #expect(fixture.taskReads == 3 && commentCalls == 3)
        #expect(report.isError == true && report.advisory && report.keyState == "unchecked")
        try fixture.assertUntouched()
    }

    @Test(arguments: [false, true])
    func commentCoveredRevisionBeforeProjection(includeComments: Bool) throws {
        let fixture = try Fixture()
        let revision = try fixture.revision()
        let report = try fixture.preview([fixture.item()], includeComments: includeComments)
        let current = try #require(report.entries[0].current)
        #expect(Fixture.field("revision", current) == .string(revision))
        if includeComments {
            guard case .array(let comments) = Fixture.field("comments", current) else {
                Issue.record("Full preview must include saved comments"); return
            }
            #expect(comments.count == 2)
        } else { #expect(Fixture.field("comments", current) == nil) }
        #expect(fixture.commentReads == 1)
        try fixture.assertUntouched()
    }

    @Test(arguments: ["task", "comment", "milestone"])
    func requiredReadFailureIsUnavailable(stage: String) throws {
        let fixture = try Fixture()
        let item = try fixture.item(changes: ["milestoneDisplayId": 9])
        if stage == "task" { fixture.taskFault = fixture.targets[0].id }
        if stage == "comment" { fixture.commentFault = fixture.targets[0].id }
        if stage == "milestone" { fixture.milestoneFault = true }
        let report = try fixture.preview([item], includeComments: false)
        #expect(report.entries[0].state == .unavailable)
        #expect(report.entries[0].proposedEffects == nil)
        #expect(report.isError == true)
        try fixture.assertUntouched()
    }

    @Test
    func staleRevisionPrecedesInvalidDomain() throws {
        let fixture = try Fixture()
        let report = try fixture.preview([fixture.item(changes: [
            "expectedRevision": MCPBatchTaskRequestFixtures.revision, "priority": "invalid"
        ])])
        #expect(report.entries[0].state == .invalid)
        #expect(report.entries[0].code == "REVISION_CONFLICT")
        #expect(report.entries[0].current != nil)
        #expect(report.entries[0].proposedEffects == nil)
        try fixture.assertUntouched()
    }

    @Test
    func fallbackHasNoSavedEvidenceOrReads() throws {
        let fixture = try Fixture()
        let report = try fixture.preview([fixture.item(), fixture.item(1)], fallback: true)
        #expect(report.entries.map(\.state) == [.unavailable, .unavailable])
        #expect(report.entries.allSatisfy { $0.code == "PERSISTENCE_UNAVAILABLE" && $0.current == nil })
        #expect(fixture.taskReads == 0 && fixture.commentReads == 0 && fixture.milestoneReads == 0)
        #expect(report.observation == "saved_local_store" && report.keyState == "unchecked" && report.advisory)
        #expect(report.isError == true)
        try fixture.assertUntouched()
    }

    @Test
    func independentSavedCommentInvalidatesEarlierRevision() throws {
        let fixture = try Fixture()
        let item = try fixture.item()
        let first = try fixture.preview([item], includeComments: false)
        #expect(first.entries[0].state == .valid)
        let independent = try Fixture.diskOwner(fixture.storeURL)
        let id = fixture.targets[0].id
        let task = try #require(independent.context.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == id })).first)
        let comment = Comment(content: "Later saved evidence", authorName: "Other", isAgent: false, task: task)
        independent.context.insert(comment)
        try independent.context.save()
        let second = try fixture.preview([item], includeComments: false)
        #expect(second.entries[0].state == .invalid)
        #expect(second.entries[0].code == "REVISION_CONFLICT")
        #expect(Fixture.field("revision", first.entries[0].current)
                != Fixture.field("revision", second.entries[0].current))
        #expect(fixture.privateContexts.count == 2)
        #expect(fixture.privateContexts.allSatisfy { !$0.hasChanges })
    }

    @Test(arguments: ["trim", "clear", "metadata", "clearMilestone", "displayPrecedence", "comment"])
    // Each branch asserts a different operation's exact proposed effect.
    // swiftlint:disable:next cyclomatic_complexity
    func proposedEffectsAreNormalizedValuesOnly(scenario: String) throws {
        let fixture = try Fixture()
        let changes: [String: Any]
        switch scenario {
        case "trim": changes = ["name": " Name ", "description": " Description "]
        case "clear": changes = ["description": " \n\t "]
        case "metadata": changes = ["metadata": [:] as [String: String]]
        case "clearMilestone": changes = ["clearMilestone": true, "milestoneDisplayId": 999, "milestone": "Missing"]
        case "displayPrecedence": changes = ["milestoneDisplayId": 9, "milestone": "Missing"]
        default: changes = ["content": " Reason \n", "authorName": " Agent \t"]
        }
        let operation = scenario == "comment" ? "add_comment" : "update_task"
        let report = try fixture.preview([fixture.item(operation: operation, changes: changes)])
        let entry = report.entries[0]
        #expect(entry.state == .valid)
        let effects = try #require(entry.proposedEffects)
        if scenario == "trim" {
            #expect(Fixture.field("name", effects) == .string("Name"))
            #expect(Fixture.field("description", effects) == .string("Description"))
        }
        if scenario == "clear" { #expect(Fixture.field("description", effects) == .null) }
        if scenario == "metadata" { #expect(Fixture.field("metadata", effects) == .null) }
        if scenario == "clearMilestone" { #expect(Fixture.field("milestone", effects) == .null) }
        if scenario == "displayPrecedence" {
            #expect(Fixture.field("milestoneId", effects) == .string(fixture.milestone.id.uuidString))
        }
        if scenario == "comment" {
            #expect(Fixture.field("content", effects) == .string("Reason"))
            #expect(Fixture.field("authorName", effects) == .string("Agent"))
            #expect(Fixture.field("isAgent", effects) == .boolean(true))
        }
        for field in ["commentId", "creationDate", "lastStatusChangeDate", "completionDate", "displayId"] {
            #expect(Fixture.field(field, effects) == nil)
        }
        try fixture.assertUntouched()
    }
}
// swiftlint:enable type_body_length
#endif
