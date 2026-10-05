import Foundation
import SwiftData
import Testing
@testable import Transit

/// Task 1 source preparation. Missing registered entities must fail at runtime,
/// not by referring to model types that have not been implemented yet.
/// Disk baseline observation below is not a closed-store migration test.
@MainActor @Suite(.serialized)
struct TaskLinkMigrationTests {
    @Test(arguments: ["TaskLinkOccurrence", "TaskLinkRemovalEvidence"])
    func defaultSchemaRegistersCloudCompatibleLinkEntity(name: String) throws {
        let fixture = try TestModelContainer()
        let entity = try #require(fixture.container.schema.entitiesByName[name])
        let occurrenceFields: Set<String> = [
            "id", "kindRawValue", "sourceTaskID", "targetTaskID", "createdAt"
        ]
        let removalFields = occurrenceFields.union(["edgeId", "occurrenceRevision", "removedAt"])
        let expectedFields = name == "TaskLinkOccurrence" ? occurrenceFields : removalFields
        let expectedTypes: [String: Any.Type] = [
            "id": UUID.self, "kindRawValue": String.self, "sourceTaskID": UUID.self,
            "targetTaskID": UUID.self, "createdAt": Date.self, "edgeId": UUID.self,
            "occurrenceRevision": String.self, "removedAt": Date.self
        ]
        #expect(Set(entity.attributes.map(\.name)) == expectedFields)
        #expect(entity.relationships.isEmpty)
        #expect(entity.uniquenessConstraints.isEmpty)
        for attribute in entity.attributes {
            #expect(!attribute.isUnique)
            #expect(attribute.isOptional || attribute.defaultValue != nil)
            let expectedType = try #require(expectedTypes[attribute.name])
            #expect(ObjectIdentifier(attribute.valueType) == ObjectIdentifier(expectedType))
        }
    }

    @Test func preFeatureDiskBaselinePreservesRawFieldsAndReceiptBytes() throws {
        let fixture = try TaskLinkPreFeatureDiskFixture()
        #expect(Set(fixture.owner.container.schema.entities.map(\.name)) == [
            "Project", "TransitTask", "Comment", "Milestone", "SyncHeartbeat", "MCPWriteReceipt"
        ])
        let expected = try fixture.savedFields(in: fixture.owner.context)
        try fixture.owner.context.save()
        #expect(FileManager.default.fileExists(atPath: fixture.storeURL.path))

        // A fresh context avoids registered object identity reuse. The owning
        // container remains open, so this proves saved observation only.
        let observer = ModelContext(fixture.owner.container)
        observer.autosaveEnabled = false
        #expect(try fixture.savedFields(in: observer) == expected)
        let tasks = try observer.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.id)).count == 1)
        #expect(Set(tasks.map(\.permanentDisplayId)).count == 1)
        #expect(!observer.hasChanges)
        #expect(!fixture.owner.context.hasChanges)
    }
}

/// Synthetic six-entity schema matching 201205bd's pre-link store. This schema
/// intentionally stays graph-free after the default test fixture is upgraded.
/// Every context is backed by the centrally retained owning TestModelContainer.
@MainActor
struct TaskLinkPreFeatureDiskFixture {
    let owner: TestModelContainer
    let storeURL: URL

    init(directory suppliedDirectory: URL? = nil, schema suppliedSchema: Schema? = nil,
         seed: Bool = true) throws {
        let directory = suppliedDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskLinkMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("pre-feature.store")
        let schema = suppliedSchema ?? Schema([
            Project.self, TransitTask.self, Transit.Comment.self, Milestone.self,
            SyncHeartbeat.self, MCPWriteReceipt.self
        ])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        owner = try TestModelContainer(schema: schema, configurations: [configuration])
        owner.context.autosaveEnabled = false
        if seed { seedRows(in: owner.context) }
        // Do not unlink an open SQLite store. TestModelContainer retains it for
        // the process lifetime; all files live in a unique system temp directory.
    }

    private func seedRows(in context: ModelContext) {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let project = Project(name: "Migration", description: "original project",
                              gitRepo: "/synthetic/repo", colorHex: "#123456")
        let milestone = Milestone(name: "Original milestone", description: "preserve",
                                  project: project, displayID: .permanent(41))
        milestone.creationDate = instant
        milestone.lastStatusChangeDate = instant
        let task = TransitTask(name: "Original task", description: "Unicode: café\nsecond line",
                               type: .feature, project: project, displayID: .permanent(42))
        task.milestone = milestone
        task.statusRawValue = "done"
        task.priorityRawValue = "legacy-priority"
        task.creationDate = instant
        task.lastStatusChangeDate = instant
        task.completionDate = instant
        task.metadataJSON = "{ \"original\" : \"bytes\" }"
        let duplicate = TransitTask(name: "Physical duplicate", type: .bug,
                                    project: project, displayID: .permanent(42))
        duplicate.id = task.id
        duplicate.statusRawValue = "future-status"
        duplicate.typeRawValue = "future-type"
        duplicate.creationDate = instant
        duplicate.lastStatusChangeDate = instant
        let comment = Transit.Comment(content: "Saved comment\nnot normalized", authorName: "Agent",
                                      isAgent: true, task: task)
        comment.creationDate = instant
        let receipt = MCPWriteReceipt(localScopeID: "synthetic-origin", tool: "update_task",
                                      key: "migration-original", requestJSON: "{ \"n\":9007199254740993 }",
                                      acceptedAt: instant)
        receipt.stateRawValue = "committed"
        receipt.completedAt = instant
        receipt.expiresAt = instant.addingTimeInterval(7 * 24 * 60 * 60)
        receipt.resultJSON = "{\n  \"outcome\": \"committed\", \"original\": \"café\"\n}\n"
        receipt.resultIsError = false
        let heartbeat = SyncHeartbeat()
        heartbeat.lastBeat = instant
        context.insert(project)
        context.insert(milestone)
        context.insert(task)
        context.insert(duplicate)
        context.insert(comment)
        context.insert(receipt)
        context.insert(heartbeat)
    }

    /// Raw stored values, not effective status/priority/metadata accessors or a
    /// current MCP encoder that could normalize historical content. Receipt JSON
    /// strings remain byte-sensitive, including whitespace and Unicode.
    func savedFields(in context: ModelContext) throws -> Data {
        let projects = try context.fetch(FetchDescriptor<Project>()).map { project in
            ["id": project.id.uuidString, "name": project.name,
             "description": project.projectDescription, "gitRepo": optional(project.gitRepo),
             "colorHex": project.colorHex] as [String: Any]
        }
        let milestones = try context.fetch(FetchDescriptor<Milestone>()).map { milestone in
            ["id": milestone.id.uuidString, "displayId": optional(milestone.permanentDisplayId),
             "name": milestone.name, "description": optional(milestone.milestoneDescription),
             "status": milestone.statusRawValue, "created": milestone.creationDate.timeIntervalSince1970,
             "changed": milestone.lastStatusChangeDate.timeIntervalSince1970,
             "completed": optional(milestone.completionDate?.timeIntervalSince1970),
             "project": optional(milestone.project?.id.uuidString)] as [String: Any]
        }
        let tasks = try context.fetch(FetchDescriptor<TransitTask>()).sorted { $0.name < $1.name }.map { task in
            ["id": task.id.uuidString, "displayId": optional(task.permanentDisplayId), "name": task.name,
             "description": optional(task.taskDescription), "status": task.statusRawValue,
             "type": task.typeRawValue, "priority": task.priorityRawValue,
             "created": task.creationDate.timeIntervalSince1970,
             "changed": task.lastStatusChangeDate.timeIntervalSince1970,
             "completed": optional(task.completionDate?.timeIntervalSince1970),
             "metadataJSON": optional(task.metadataJSON), "project": optional(task.project?.id.uuidString),
             "milestone": optional(task.milestone?.id.uuidString),
             "comments": (task.comments ?? []).map { $0.id.uuidString }.sorted()] as [String: Any]
        }
        let comments = try context.fetch(FetchDescriptor<Transit.Comment>()).map { comment in
            ["id": comment.id.uuidString, "content": comment.content, "author": comment.authorName,
             "isAgent": comment.isAgent, "created": comment.creationDate.timeIntervalSince1970,
             "task": optional(comment.task?.id.uuidString)] as [String: Any]
        }
        let receipts = try context.fetch(FetchDescriptor<MCPWriteReceipt>()).map { receipt in
            ["id": receipt.id.uuidString, "scope": receipt.localScopeID, "tool": receipt.tool,
             "key": receipt.key, "version": receipt.formatVersion, "requestJSON": receipt.requestJSON,
             "state": receipt.stateRawValue, "accepted": receipt.acceptedAt.timeIntervalSince1970,
             "completed": optional(receipt.completedAt?.timeIntervalSince1970),
             "expires": optional(receipt.expiresAt?.timeIntervalSince1970),
             "resultJSON": optional(receipt.resultJSON), "isError": optional(receipt.resultIsError)] as [String: Any]
        }
        let heartbeats = try context.fetch(FetchDescriptor<SyncHeartbeat>()).map { heartbeat in
            ["id": heartbeat.id, "lastBeat": heartbeat.lastBeat.timeIntervalSince1970] as [String: Any]
        }
        return try JSONSerialization.data(withJSONObject: [
            "projects": projects, "milestones": milestones, "tasks": tasks,
            "comments": comments, "receipts": receipts, "heartbeats": heartbeats
        ], options: [.sortedKeys])
    }

    private func optional<T>(_ value: T?) -> Any {
        if let value { return value }
        return NSNull()
    }
}
