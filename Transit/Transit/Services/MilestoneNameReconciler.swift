import Foundation
import SwiftData

/// Shared, locale-stable milestone name semantics. CloudKit peers may use
/// different user locales, so invariant checks and reconciliation must not.
@MainActor
enum MilestoneNamePolicy {
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func precedesForReconciliation(_ lhs: Milestone, _ rhs: Milestone) -> Bool {
        if lhs.creationDate != rhs.creationDate {
            return lhs.creationDate < rhs.creationDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Repairs duplicate names imported from other CloudKit devices without
/// deleting records or changing their task relationships.
@MainActor
struct MilestoneNameReconciler {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func reconcile() throws -> Int {
        // Saving this shared context would also commit unrelated edits. Defer until
        // a later lifecycle trigger if another workflow currently owns changes.
        guard !modelContext.hasChanges else { return 0 }

        let milestones = try modelContext.fetch(FetchDescriptor<Milestone>())
        let projectGroups = Dictionary(grouping: milestones) { $0.project?.id }
        var renamedCount = 0
        for projectMilestones in projectGroups.values {
            renamedCount += renameDuplicates(in: projectMilestones)
        }

        if renamedCount > 0 {
            try modelContext.saveOrRollback()
        }
        return renamedCount
    }

    private func renameDuplicates(in milestones: [Milestone]) -> Int {
        var groups: [String: [Milestone]] = [:]
        for milestone in milestones where milestone.project != nil {
            groups[MilestoneNamePolicy.normalized(milestone.name), default: []].append(milestone)
        }
        var reservedNames = Set(milestones.map { MilestoneNamePolicy.normalized($0.name) })
        var renamedCount = 0

        for nameKey in groups.keys.sorted() {
            guard let matches = groups[nameKey], matches.count > 1 else { continue }
            let ordered = matches.sorted(by: MilestoneNamePolicy.precedesForReconciliation)
            guard let winner = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                let candidate = uniqueName(for: duplicate, winner: winner, reserved: reservedNames)
                duplicate.name = candidate
                reservedNames.insert(MilestoneNamePolicy.normalized(candidate))
                renamedCount += 1
            }
        }
        return renamedCount
    }

    private func uniqueName(
        for duplicate: Milestone,
        winner: Milestone,
        reserved: Set<String>
    ) -> String {
        let base = "\(winner.name) (Duplicate \(duplicate.id.uuidString))"
        var candidate = base
        var collisionSuffix = 2
        while reserved.contains(MilestoneNamePolicy.normalized(candidate)) {
            candidate = "\(base)-\(collisionSuffix)"
            collisionSuffix += 1
        }
        return candidate
    }
}
