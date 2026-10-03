import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPRecordRevisionTests {
    @Test func taskCoveredScalarsAndRestoration() throws {
        let owner = try TestModelContainer()
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "red")
        owner.context.insert(project)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)
        owner.context.insert(task)
        let baseline = try MCPRecordSnapshot.task(task, in: owner.context)
        let changes: [(TransitTask) -> Void] = [
            { $0.id = UUID() }, { $0.name = "changed" }, { $0.taskDescription = "" },
            { $0.statusRawValue = "invalid" }, { $0.typeRawValue = "invalid" },
            { $0.priorityRawValue = "legacy" }, { $0.permanentDisplayId = 10 },
            { $0.creationDate = Date(timeIntervalSinceReferenceDate: 1) },
            { $0.lastStatusChangeDate = Date(timeIntervalSinceReferenceDate: 2) },
            { $0.completionDate = Date(timeIntervalSinceReferenceDate: 3) },
            { $0.metadataJSON = "{}" }, { $0.project = nil },
            { $0.milestone = Milestone(name: "M", project: project, displayID: .provisional) }
        ]
        for change in changes {
            let copy = TransitTask(name: task.name, type: .feature, project: project, displayID: .provisional)
            copy.id = task.id
            copy.creationDate = task.creationDate
            copy.lastStatusChangeDate = task.lastStatusChangeDate
            change(copy)
            let changed = try MCPRecordSnapshot.task(copy) { _ in [] }
            #expect(changed.revision != baseline.revision)
        }
        task.name = "changed"
        task.name = "Task"
        project.name = "rename excluded"
        #expect(try MCPRecordSnapshot.task(task, in: owner.context).revision == baseline.revision)
        task.creationDate = Date(
            timeIntervalSinceReferenceDate: task.creationDate.timeIntervalSinceReferenceDate.nextUp
        )
        #expect(try MCPRecordSnapshot.task(task, in: owner.context).revision != baseline.revision)
    }

    @Test func commentOrderAndFetchFailure() throws {
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "red")
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)
        let first = Transit.Comment(content: "one", authorName: "A", isAgent: true, task: task)
        let second = Transit.Comment(content: "two", authorName: "B", isAgent: false, task: task)
        let snapshot = try MCPRecordSnapshot.task(task) { _ in [first, second] }
        #expect(snapshot.revision == (try MCPRecordSnapshot.task(task) { _ in [second, first] }.revision))
        first.content = "changed"
        #expect(snapshot.revision != (try MCPRecordSnapshot.task(task) { _ in [first, second] }.revision))
        #expect(throws: CocoaError.self) {
            try MCPRecordSnapshot.task(task) { _ in throw CocoaError(.fileReadUnknown) }
        }
        #expect((snapshot.record["revision"] as? String) == snapshot.revision)
    }

    @Test func projectMilestoneAndCommentCoverage() throws {
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "red")
        let milestone = Milestone(name: "M", project: project, displayID: .provisional)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)
        let comment = Transit.Comment(content: "C", authorName: "A", isAgent: false, task: task)
        let baseline = try MCPRecordSnapshot.project(project).revision
        project.tasks = [task]
        project.milestones = [milestone]
        #expect(try MCPRecordSnapshot.project(project).revision == baseline)
        project.gitRepo = ""
        #expect(try MCPRecordSnapshot.project(project).revision != baseline)
        let milestoneBaseline = try MCPRecordSnapshot.milestone(milestone).revision
        milestone.tasks = [task]
        project.name = "renamed"
        #expect(try MCPRecordSnapshot.milestone(milestone).revision == milestoneBaseline)
        milestone.project = nil
        #expect(try MCPRecordSnapshot.milestone(milestone).revision != milestoneBaseline)
        let commentBaseline = try MCPRecordSnapshot.comment(comment).revision
        comment.isAgent = true
        #expect(try MCPRecordSnapshot.comment(comment).revision != commentBaseline)
    }

    @Test func everyProjectMilestoneAndCommentScalarChangesItsToken() throws {
        let owner = try TestModelContainer()
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "red")
        let milestone = Milestone(name: "M", project: project, displayID: .provisional)
        let task = TransitTask(name: "T", type: .feature, project: project, displayID: .provisional)
        let comment = Transit.Comment(content: "C", authorName: "A", isAgent: false, task: task)
        owner.context.insert(project)
        owner.context.insert(milestone)
        owner.context.insert(task)
        owner.context.insert(comment)
        try owner.context.save()
        let projectBaseline = try MCPRecordSnapshot.project(project).revision
        let projectChanges: [(Project) -> Void] = [
            { $0.id = UUID() }, { $0.name = "new" }, { $0.projectDescription = "new" },
            { $0.gitRepo = "" }, { $0.colorHex = "blue" }
        ]
        for change in projectChanges {
            change(project)
            #expect(try MCPRecordSnapshot.project(project).revision != projectBaseline)
            owner.context.safeRollback()
        }
        let milestoneBaseline = try MCPRecordSnapshot.milestone(milestone).revision
        let milestoneChanges: [(Milestone) -> Void] = [
            { $0.id = UUID() }, { $0.name = "new" }, { $0.milestoneDescription = "" },
            { $0.permanentDisplayId = 4 }, { $0.statusRawValue = "invalid" },
            { $0.creationDate = .distantPast }, { $0.lastStatusChangeDate = .distantPast },
            { $0.completionDate = .distantPast }, { $0.project = nil }
        ]
        for change in milestoneChanges {
            change(milestone)
            #expect(try MCPRecordSnapshot.milestone(milestone).revision != milestoneBaseline)
            owner.context.safeRollback()
        }
        let commentBaseline = try MCPRecordSnapshot.comment(comment).revision
        let commentChanges: [(Transit.Comment) -> Void] = [
            { $0.id = UUID() }, { $0.content = "new" }, { $0.authorName = "new" },
            { $0.isAgent = true }, { $0.creationDate = .distantPast }, { $0.task = nil }
        ]
        for change in commentChanges {
            change(comment)
            #expect(try MCPRecordSnapshot.comment(comment).revision != commentBaseline)
            owner.context.safeRollback()
        }
    }
}
