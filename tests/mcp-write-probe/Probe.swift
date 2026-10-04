import Foundation
import SwiftData
import Darwin

/// A separate process is essential: retained containers must not turn a reopen
/// into a cache read, and SIGKILL must bypass normal shutdown/checkpointing.
@main
struct MCPWriteDiskProbe {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        let mode = arguments[1]
        let url = URL(fileURLWithPath: arguments[2])
        var models: [any PersistentModel.Type] = [
            Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self
        ]
        if mode != "seed-old" {
            models.append(MCPWriteReceipt.self)
            models.append(TaskLinkOccurrence.self)
            models.append(TaskLinkRemovalEvidence.self)
        }
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, url: url,
                                               allowsSave: mode != "readonly", cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false

        switch mode {
        case "seed-old": try seedOld(context: context)
        case "stage": try stage(context: context)
        case "verify": try verify(context: context)
        case "cleanup": try cleanup(container: container)
        case "readonly": try readOnly(context: context)
        case "verify-clean": try verifyClean(context: context)
        default: fatalError("Unknown mode")
        }
    }

    @MainActor static func seedOld(context: ModelContext) throws {
        let project = Project(name: "Disk", description: "preserved", gitRepo: nil, colorHex: "#123456")
        let task = TransitTask(name: "Baseline", type: .feature, project: project, displayID: .permanent(1))
        context.insert(project)
        context.insert(task)
        try context.save()
    }

    @MainActor static func stage(context: ModelContext) throws {
        let task = try context.fetch(FetchDescriptor<TransitTask>())[0]
        let receipt = MCPWriteReceipt(localScopeID: "probe", tool: "update_task_status", key: "crash",
                                      requestJSON: "{}", acceptedAt: Date())
        context.insert(receipt)
        try context.save()
        task.status = .done
        task.completionDate = Date(timeIntervalSinceReferenceDate: 10)
        for index in 0..<200 {
            context.insert(Comment(content: "comment-\(index)", authorName: "Probe", isAgent: true, task: task))
        }
        receipt.stateRawValue = "committed"
        receipt.completedAt = Date(timeIntervalSinceReferenceDate: 10)
        receipt.expiresAt = Date(timeIntervalSinceReferenceDate: 604810)
        receipt.resultJSON = "{\"outcome\":\"committed\"}"
        receipt.resultIsError = false
        print("STAGED")
        fflush(stdout)
        _ = readLine()
        print("SAVING")
        fflush(stdout)
        try context.save()
        print("SAVED")
        fflush(stdout)
        _ = readLine()
    }

    @MainActor static func verify(context: ModelContext) throws {
        let tasks = try context.fetch(FetchDescriptor<TransitTask>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let comments = try context.fetch(FetchDescriptor<Comment>())
        let receipts = try context.fetch(FetchDescriptor<MCPWriteReceipt>())
        precondition(tasks.count == 1 && projects.count == 1)
        precondition(projects[0].projectDescription == "preserved")
        precondition(receipts.count == 1)
        let committed = receipts[0].stateRawValue == "committed"
        precondition(tasks[0].status == (committed ? .done : .idea))
        precondition(comments.count == (committed ? 200 : 0))
        precondition((tasks[0].completionDate != nil) == committed)
        precondition((receipts[0].resultJSON != nil) == committed)
        if committed { precondition(receipts[0].resultIsError == false) }
        print(committed ? "COMMITTED" : "ACCEPTED")
    }

    @MainActor static func cleanup(container: ModelContainer) throws {
        let context = container.mainContext
        let task = try context.fetch(FetchDescriptor<TransitTask>())[0]
        let original = task.statusRawValue
        let receipt = MCPWriteReceipt(localScopeID: "probe", tool: "add_comment", key: "failure",
                                      requestJSON: "{}", acceptedAt: Date())
        context.insert(receipt)
        try context.save()
        task.status = .done
        let comment = Comment(content: "ghost", authorName: "Probe", isAgent: true, task: task)
        context.insert(comment)
        receipt.stateRawValue = "committed"
        // Deterministic save seam throws before commit, then the same
        // context must still support an unrelated successful save.
        do { throw CocoaError(.fileWriteNoPermission) } catch {
            context.delete(comment)
            context.safeRollback()
        }
        precondition(task.statusRawValue == original)
        precondition(receipt.stateRawValue == "accepted")
        let project = try context.fetch(FetchDescriptor<Project>())[0]
        project.name = "Unrelated saved edit"
        try context.save()
        let fresh = ModelContext(container)
        let savedComments = try fresh.fetch(FetchDescriptor<Comment>())
        let savedTasks = try fresh.fetch(FetchDescriptor<TransitTask>())
        let savedReceipts = try fresh.fetch(FetchDescriptor<MCPWriteReceipt>())
        precondition(savedComments.isEmpty)
        precondition(savedTasks[0].statusRawValue == original)
        precondition(savedReceipts[0].stateRawValue == "accepted")
        print("CLEAN")
    }

    @MainActor static func readOnly(context: ModelContext) throws {
        let task = try context.fetch(FetchDescriptor<TransitTask>())[0]
        task.status = .done
        let receipt = MCPWriteReceipt(localScopeID: "probe", tool: "add_comment", key: "readonly",
                                      requestJSON: "{}", acceptedAt: Date())
        let comment = Comment(content: "ghost", authorName: "Probe", isAgent: true, task: task)
        context.insert(receipt)
        context.insert(comment)
        do {
            try context.save()
            fatalError("Read-only save unexpectedly succeeded")
        } catch {
            context.delete(comment)
            context.delete(receipt)
            context.safeRollback()
        }
        print("FAILED_AS_EXPECTED")
    }

    @MainActor static func verifyClean(context: ModelContext) throws {
        let tasks = try context.fetch(FetchDescriptor<TransitTask>())
        let comments = try context.fetch(FetchDescriptor<Comment>())
        let receipts = try context.fetch(FetchDescriptor<MCPWriteReceipt>())
        precondition(tasks[0].status == .idea && comments.isEmpty && receipts.isEmpty)
        let project = try context.fetch(FetchDescriptor<Project>())[0]
        project.name = "Later unrelated save"
        try context.save()
        print("CLEAN")
    }
}
