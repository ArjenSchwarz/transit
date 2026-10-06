import Foundation

/// Aggregate copied-value accounting during the synchronous saved boundary.
/// The exact complete wrapper is still measured before publication.
@MainActor final class ConsolidationCaptureCharge {
    let budget: TaskLinkGraphBudget
    private var copiedBytes = 0

    init(budget: TaskLinkGraphBudget) { self.budget = budget }

    func checkAdditional(_ bytes: Int) throws {
        try budget.check()
        let (total, overflow) = copiedBytes.addingReportingOverflow(bytes)
        guard bytes >= 0, !overflow, total <= budget.maximumBytes else {
            throw TaskLinkGraphError.capacityExceeded
        }
    }

    func append(_ bytes: Int) throws {
        try checkAdditional(bytes)
        copiedBytes += bytes
    }
}
