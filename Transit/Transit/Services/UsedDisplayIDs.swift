import Foundation
import SwiftData

/// The permanent display IDs already committed to the local store.
///
/// Supplied to `DisplayIDAllocator.allocateNextID(excluding:)`, where it is the
/// collision guard against a stale or stuck CloudKit counter (T-1395): the
/// allocator skips past any candidate this set already contains.
///
/// A fetch failure **throws** rather than degrading to an empty set. An empty set
/// is indistinguishable from "no IDs are in use", which silently disables the
/// guard and lets the allocator hand back an ID a local record already holds —
/// and SwiftData + CloudKit cannot express `@Attribute(.unique)`, so nothing
/// downstream would catch the duplicate (T-1621).
struct UsedDisplayIDs {

    private let fetcher: any ModelFetching

    init(_ fetcher: any ModelFetching) {
        self.fetcher = fetcher
    }

    func tasks() throws -> Set<Int> {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        return Set(try fetcher.fetch(descriptor).compactMap(\.permanentDisplayId))
    }

    func milestones() throws -> Set<Int> {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        return Set(try fetcher.fetch(descriptor).compactMap(\.permanentDisplayId))
    }
}
