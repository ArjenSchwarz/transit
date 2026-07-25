import Foundation
import SwiftData

/// Narrow seam over `ModelContext.fetch` for the service-layer helpers that
/// enforce invariants from a fetch result.
///
/// Those helpers must be able to tell "the store says nothing matched" apart from
/// "the store could not be read". `(try? fetch(...)) ?? []` collapses the two, and
/// every caller then treats the failure as an authoritative negative answer
/// (T-1614, T-1621). Fetching through this protocol keeps the `throws` and lets
/// tests inject a failing store without a broken `ModelContainer`.
///
/// `ModelContext` conforms directly, so production code passes the real context.
@MainActor
protocol ModelFetching {
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T]
}

extension ModelContext: ModelFetching {}
