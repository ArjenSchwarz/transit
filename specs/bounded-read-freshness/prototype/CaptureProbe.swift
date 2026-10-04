// DESIGN PROTOTYPE ONLY: isolated on-disk store, CloudKit disabled, no Transit models.
import Foundation
import SwiftData

@Model final class ProbeProject {
    var name: String = ""
    init(name: String) { self.name = name }
}
@Model final class ProbeTask {
    var projectName: String = ""
    init(projectName: String) { self.projectName = projectName }
}

@main struct CaptureProbe {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([ProbeProject.self, ProbeTask.self])
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let project = ProbeProject(name: "old")
        let task = ProbeTask(projectName: "old")
        writer.insert(project); writer.insert(task)
        try writer.save()
        func watermark(_ context: ModelContext) throws -> DefaultHistoryTransaction? {
            var d = HistoryDescriptor<DefaultHistoryTransaction>(sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)])
            d.fetchLimit = 1
            return try context.fetchHistory(d).first
        }
        func capture(injectWrite: Bool) throws -> (consistent: Bool, names: [String], store: String) {
            let before = try watermark(ModelContext(container))
            let reader = ModelContext(container)
            reader.autosaveEnabled = false
            let projects = try reader.fetch(FetchDescriptor<ProbeProject>()).map(\.name)
            if injectWrite {
                project.name = "new"; task.projectName = "new"
                try writer.save()
            }
            let tasks = try reader.fetch(FetchDescriptor<ProbeTask>()).map(\.projectName)
            let after = try watermark(ModelContext(container))
            let coherent = before?.token == after?.token && before?.storeIdentifier == after?.storeIdentifier
            return (coherent, projects + tasks, after?.storeIdentifier ?? "unknown")
        }
        let mixed = try capture(injectWrite: true)
        precondition(!mixed.consistent, "a saved change spanning selected tables must invalidate capture")
        let stable = try capture(injectWrite: false)
        precondition(stable.consistent && stable.names == ["new", "new"])
        print("PASS mixed_capture_rejected=true fresh_saved_write_visible=true stable_history_watermark=true store_identifier_known=\(!stable.store.isEmpty && stable.store != "unknown") mixed_values=\(mixed.names) stable_values=\(stable.names)")
    }
}
