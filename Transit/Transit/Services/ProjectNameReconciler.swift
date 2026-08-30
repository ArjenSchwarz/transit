import Foundation
import SwiftData

/// Shared, locale-stable project name semantics. CloudKit peers may use
/// different user locales, so invariant checks and reconciliation must not.
@MainActor
enum ProjectNamePolicy {
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func precedesForReconciliation(_ lhs: Project, _ rhs: Project) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Repairs duplicate names imported from other CloudKit devices without
/// deleting projects or changing their task and milestone relationships.
@MainActor
struct ProjectNameReconciler {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func reconcile() throws -> Int {
        // Saving this shared context would also commit unrelated edits. Defer until
        // a later lifecycle or query-observer trigger if another workflow owns changes.
        guard !modelContext.hasChanges else { return 0 }

        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        var groups: [String: [Project]] = [:]
        for project in projects {
            groups[ProjectNamePolicy.normalized(project.name), default: []].append(project)
        }
        var reservedNames = Set(projects.map { ProjectNamePolicy.normalized($0.name) })
        var renamedCount = 0

        for nameKey in groups.keys.sorted() {
            guard let matches = groups[nameKey], matches.count > 1 else { continue }
            let ordered = matches.sorted(by: ProjectNamePolicy.precedesForReconciliation)
            guard let winner = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                let candidate = uniqueName(for: duplicate, winner: winner, reserved: reservedNames)
                duplicate.name = candidate
                reservedNames.insert(ProjectNamePolicy.normalized(candidate))
                renamedCount += 1
            }
        }

        if renamedCount > 0 {
            try modelContext.saveOrRollback()
        }
        return renamedCount
    }

    private func uniqueName(
        for duplicate: Project,
        winner: Project,
        reserved: Set<String>
    ) -> String {
        let base = "\(winner.name) (Duplicate \(duplicate.id.uuidString))"
        var candidate = base
        var collisionSuffix = 2
        while reserved.contains(ProjectNamePolicy.normalized(candidate)) {
            candidate = "\(base)-\(collisionSuffix)"
            collisionSuffix += 1
        }
        return candidate
    }
}
