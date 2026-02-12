import AppIntents
import Foundation
import SwiftData

struct TaskEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        Self.entities(for: identifiers, modelContext: projectService.context)
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        Self.suggestedEntities(modelContext: projectService.context)
    }

    @MainActor
    static func entities(for identifiers: [String], modelContext: ModelContext) -> [TaskEntity] {
        if identifiers.isEmpty {
            return []
        }

        var wantedIDs = Set<UUID>()
        wantedIDs.reserveCapacity(identifiers.count)
        for identifier in identifiers {
            if let uuid = UUID(uuidString: identifier) {
                wantedIDs.insert(uuid)
            }
        }

        if wantedIDs.isEmpty {
            return []
        }

        let tasks = (try? modelContext.fetch(FetchDescriptor<TransitTask>())) ?? []
        let matchingTasks = tasks.filter { wantedIDs.contains($0.id) }
        return entities(from: matchingTasks)
    }

    @MainActor
    static func suggestedEntities(modelContext: ModelContext) -> [TaskEntity] {
        let descriptor = FetchDescriptor<TransitTask>(
            sortBy: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)]
        )

        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        if tasks.isEmpty {
            return []
        }

        return entities(from: Array(tasks.prefix(10)))
    }

    static func entities(from tasks: [TransitTask]) -> [TaskEntity] {
        if tasks.isEmpty {
            return []
        }

        var entities: [TaskEntity] = []
        entities.reserveCapacity(tasks.count)
        for task in tasks {
            if let entity = try? TaskEntity.from(task) {
                entities.append(entity)
            }
        }
        return entities
    }
}
