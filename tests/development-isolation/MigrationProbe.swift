import Foundation
import SwiftData

/// A standalone executable with no app lifecycle, entitlement or CloudKit connection.
@main
struct MigrationProbe {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 3)
        let mode = arguments[1]
        let root = ProcessInfo.processInfo.environment["TRANSIT_DISPOSABLE_ROOT"]!
        let url = try DisposableStorePath.resolve(path: arguments[2], rootPath: root)
        if mode == "path-guard" {
            try verifyPathGuard(root: URL(fileURLWithPath: root))
            print("Path guard checks passed: aliases, new/existing leaves, escape and symlink rejection")
            return
        }
        var models: [any PersistentModel.Type] = [
            Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self
        ]
        if mode == "open-new" || mode == "configuration" { models.append(MCPWriteReceipt.self) }
        let schema = Schema(models)
        let configuration = mode == "configuration"
            ? try IsolatedPersistenceConfiguration.make(mode: .development, schema: schema,
                                                        applicationSupportDirectory: url.deletingLastPathComponent())
            : ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        switch mode {
        case "configuration":
            try verifyConfiguration(schema: schema, configuration: configuration, url: url)
        case "seed-old":
            let project = Project(name: "Synthetic", description: "Disposable verification",
                                  gitRepo: nil, colorHex: "#123456")
            let task = TransitTask(name: "Synthetic task", type: .feature,
                                   project: project, displayID: .permanent(1))
            context.insert(project)
            context.insert(task)
            try context.save()
            try report(context, phase: mode)
        case "hold-old":
            try report(context, phase: "READY")
            while let command = readLine() {
                if command == "read" { try report(ModelContext(container), phase: "READ") }
                if command == "quit" { break }
            }
        case "open-new":
            try report(context, phase: "before-new-save")
            context.insert(MCPWriteReceipt(localScopeID: "synthetic", tool: "probe", key: "synthetic-key",
                                           requestJSON: "{}", acceptedAt: Date()))
            try context.save()
            let receipt = try context.fetch(FetchDescriptor<MCPWriteReceipt>()).first!
            precondition(receipt.key == "synthetic-key" && receipt.stateRawValue == "accepted")
            try report(context, phase: mode, receipt: receipt)
        default: fatalError("Unsupported probe mode")
        }
    }

    static func verifyPathGuard(root: URL) throws {
        let files = FileManager.default
        let allowed = root.appendingPathComponent("guard-allowed", isDirectory: true)
        let sibling = root.appendingPathComponent("guard-allowed-sibling", isDirectory: true)
        try files.createDirectory(at: allowed, withIntermediateDirectories: true)
        try files.createDirectory(at: sibling, withIntermediateDirectories: true)
        let leaf = allowed.appendingPathComponent("synthetic.store")
        let new = try DisposableStorePath.resolve(path: leaf.path, rootPath: allowed.path)
        let alias = allowed.resolvingSymlinksInPath()
        let aliased = try DisposableStorePath.resolve(path: leaf.path, rootPath: alias.path)
        precondition(aliased == new)
        try Data().write(to: new)
        let existing = try DisposableStorePath.resolve(path: leaf.path, rootPath: allowed.path)
        precondition(existing == new)
        func rejects(_ path: URL, expected: DisposableStorePath.Failure) throws {
            do {
                _ = try DisposableStorePath.resolve(path: path.path, rootPath: allowed.path)
                fatalError("Unsafe path accepted")
            } catch let error as DisposableStorePath.Failure {
                precondition(error == expected)
            }
        }
        try rejects(sibling.appendingPathComponent("synthetic.store"), expected: .outsideRoot)
        try rejects(allowed.appendingPathComponent("wrong.store"), expected: .invalidName)
        try rejects(allowed.appendingPathComponent("missing/synthetic.store"), expected: .missingDirectory)
        try files.removeItem(at: new)
        try files.createSymbolicLink(at: leaf, withDestinationURL: sibling.appendingPathComponent("missing.store"))
        try rejects(leaf, expected: .symbolicLink)
        try files.removeItem(at: leaf)
        try files.createSymbolicLink(at: leaf, withDestinationURL: sibling)
        try rejects(leaf, expected: .symbolicLink)
        let escape = allowed.appendingPathComponent("escape", isDirectory: true)
        try files.createSymbolicLink(at: escape, withDestinationURL: sibling)
        try rejects(escape.appendingPathComponent("synthetic.store"), expected: .outsideRoot)
    }

    @MainActor static func verifyConfiguration(
        schema: Schema, configuration: ModelConfiguration, url: URL
    ) throws {
        let expected = url.deletingLastPathComponent()
            .appendingPathComponent("TransitDevelopment/development.store")
        precondition(configuration.url == expected && !configuration.isStoredInMemoryOnly)
        precondition(configuration.cloudKitContainerIdentifier == nil)
        precondition(configuration.groupAppContainerIdentifier == nil)
        let cloud = try IsolatedPersistenceConfiguration.make(mode: .development, schema: schema,
            applicationSupportDirectory: url.deletingLastPathComponent(),
            cloudKitContainerID: AppPersistencePolicy.Mode.development.cloudKitContainerID)
        precondition(cloud.url == configuration.url && cloud.groupAppContainerIdentifier == nil)
        precondition(cloud.cloudKitContainerIdentifier == "iCloud.me.nore.ig.Transit.development")
        // Inspect the configuration only; never construct a cloud-backed container.

        for mode in [AppPersistencePolicy.Mode.unitTest, .uiTest] {
            let memory = try IsolatedPersistenceConfiguration.make(mode: mode, schema: schema)
            precondition(memory.isStoredInMemoryOnly)
            let isolated = try ModelContainer(for: schema, configurations: memory)
            let project = Project(name: "Memory synthetic", description: "", gitRepo: nil, colorHex: "#123456")
            isolated.mainContext.insert(project)
            try isolated.mainContext.save()
            let count = try isolated.mainContext.fetchCount(FetchDescriptor<Project>())
            precondition(count == 1)
        }
        print("Actual isolated configuration checks passed")
    }

    @MainActor static func report(_ context: ModelContext, phase: String, receipt: MCPWriteReceipt? = nil) throws {
        let tasks = try context.fetch(FetchDescriptor<TransitTask>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        var result: [String: Any] = [
            "phase": phase, "taskCount": tasks.count, "projectCount": projects.count,
            "taskIDs": tasks.map { $0.id.uuidString }, "projectNames": projects.map(\.name),
            "linkedProjectNames": tasks.map { $0.project?.name ?? "missing" },
            "taskRecords": tasks.map { ["id": $0.id.uuidString,
                                        "displayID": $0.permanentDisplayId as Any? ?? NSNull(),
                                        "status": $0.statusRawValue,
                                        "projectID": $0.project?.id.uuidString as Any? ?? NSNull()] }
        ]
        // A named synthetic projection uses the production revision algorithm;
        // it is not advertised as a complete task revision from a live tool.
        result["projectionRevisions"] = try tasks.map { task in
            try MCPRecordRevision.token(entity: "syntheticTaskProjection", fields: [
                "id": MCPRecordRevision.uuid(task.id), "name": task.name,
                "displayID": task.permanentDisplayId as Any? ?? NSNull(),
                "status": task.statusRawValue, "projectID": MCPRecordRevision.uuid(task.project?.id),
                "creationDate": try MCPRecordRevision.exactDate(task.creationDate),
                "lastStatusChangeDate": try MCPRecordRevision.exactDate(task.lastStatusChangeDate)
            ])
        }
        if let receipt {
            result["receipt"] = ["id": receipt.id.uuidString, "key": receipt.key, "state": receipt.stateRawValue]
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        fflush(stdout)
    }
}
