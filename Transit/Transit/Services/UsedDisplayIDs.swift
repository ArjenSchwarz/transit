import Foundation
import SwiftData

/// The permanent display IDs that must block an allocation candidate.
///
/// SwiftData's main `ModelContext` can keep registered `@Model` values that lag
/// peer changes already committed to the local store. It is still authoritative
/// for live/pending values that have not been saved. Build the guard from both:
/// a fresh transient context reads committed rows without registered-object
/// caching, then the live fetcher contributes current in-process values (T-1939).
///
/// `DisplayIDAllocator` unions this set with IDs it has issued but not yet seen
/// committed. Together those three sources close the stale counter and
/// allocate-before-save collision windows.
///
/// Either fetch failing **throws** rather than degrading to an empty/partial set.
/// A partial set silently disables part of the uniqueness guard, and SwiftData +
/// CloudKit cannot express `@Attribute(.unique)` to catch a duplicate later
/// (T-1621).
struct UsedDisplayIDs {

    private let modelContext: ModelContext
    private let liveFetcher: any ModelFetching

    init(modelContext: ModelContext, liveFetcher: (any ModelFetching)? = nil) {
        self.modelContext = modelContext
        self.liveFetcher = liveFetcher ?? modelContext
    }

    func tasks() throws -> Set<Int> {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        let committedContext = ModelContext(modelContext.container)
        let committed = Set(try committedContext.fetch(descriptor).compactMap(\.permanentDisplayId))
        let live = Set(try liveFetcher.fetch(descriptor).compactMap(\.permanentDisplayId))
        return committed.union(live)
    }

    func milestones() throws -> Set<Int> {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        let committedContext = ModelContext(modelContext.container)
        let committed = Set(try committedContext.fetch(descriptor).compactMap(\.permanentDisplayId))
        let live = Set(try liveFetcher.fetch(descriptor).compactMap(\.permanentDisplayId))
        return committed.union(live)
    }
}
