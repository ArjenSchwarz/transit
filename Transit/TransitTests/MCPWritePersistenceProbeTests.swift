import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPWritePersistenceProbeTests {
    private var schema: Schema {
        Schema([Project.self, TransitTask.self, Comment.self, Milestone.self,
                SyncHeartbeat.self, MCPWriteReceipt.self,
                TaskLinkOccurrence.self, TaskLinkRemovalEvidence.self])
    }

    private func diskFixture(at url: URL, writable: Bool = true) throws -> TestModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url,
                                               allowsSave: writable, cloudKitDatabase: .none)
        let fixture = try TestModelContainer(schema: schema, configurations: [configuration])
        fixture.context.autosaveEnabled = false
        return fixture
    }

    @Test func completedReceiptAndEffectReopenTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let owner = try diskFixture(at: url)
        let context = owner.context
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "#000000")
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        context.insert(project)
        context.insert(task)
        let receipt = MCPWriteReceipt(localScopeID: "scope", tool: "update_task_status", key: "key",
                                      requestJSON: "{}", acceptedAt: Date())
        context.insert(receipt)
        try context.save()
        task.status = .done
        context.insert(Transit.Comment(content: "saved", authorName: "agent", isAgent: true, task: task))
        receipt.stateRawValue = "committed"
        receipt.completedAt = Date()
        receipt.expiresAt = receipt.completedAt!.addingTimeInterval(604800)
        receipt.resultJSON = "{\"outcome\":\"committed\"}"
        receipt.resultIsError = false
        try context.save()
        let reopened = try diskFixture(at: url)
        #expect(try reopened.context.fetch(FetchDescriptor<TransitTask>())[0].status == .done)
        #expect(try reopened.context.fetch(FetchDescriptor<Transit.Comment>()).count == 1)
        let saved = try reopened.context.fetch(FetchDescriptor<MCPWriteReceipt>())[0]
        #expect(saved.resultJSON == receipt.resultJSON)
        #expect(saved.stateRawValue == "committed")
    }

    @Test func actualReadOnlySaveFailureLeavesNoDurableEffect() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly.store")
        let owner = try diskFixture(at: url)
        let project = Project(name: "Original", description: "", gitRepo: nil, colorHex: "#000000")
        owner.context.insert(project)
        try owner.context.save()
        let readOnly = try diskFixture(at: url, writable: false)
        let live = try readOnly.context.fetch(FetchDescriptor<Project>())[0]
        live.name = "Not saved"
        let receipt = MCPWriteReceipt(localScopeID: "scope", tool: "create_project", key: "failure",
                                      requestJSON: "{}", acceptedAt: Date())
        readOnly.context.insert(receipt)
        #expect(throws: (any Error).self) { try readOnly.context.save() }
        readOnly.context.delete(receipt)
        readOnly.context.safeRollback()
        let reopened = try diskFixture(at: url)
        #expect(try reopened.context.fetch(FetchDescriptor<Project>())[0].name == "Original")
        #expect(try reopened.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
        let saved = try reopened.context.fetch(FetchDescriptor<Project>())[0]
        saved.name = "Unrelated"
        try reopened.context.save()
        #expect(try reopened.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
    }
}
