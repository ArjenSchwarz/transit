import Foundation

/// Physical record identities are counted across complete change-feed pages, including later deletions.
nonisolated struct MigrationInventoryAccumulator {
    private(set) var types: [String: String] = [:]
    private(set) var counters: [String: Int] = [:]
    private var pages = 0

    mutating func record(id: String, type: String, counter: Int?) throws {
        types[id] = type
        if type == "DisplayIDCounter" {
            guard ["global-counter", "milestone-counter"].contains(id), let counter, counter > 0 else {
                throw MigrationCounterPreflight.Failure.counterReadback
            }
            counters[id] = counter
        }
        guard types.count <= 100_000 else { throw MigrationCounterPreflight.Failure.notFresh }
    }

    mutating func delete(id: String) {
        types.removeValue(forKey: id)
        counters.removeValue(forKey: id)
    }

    mutating func finishPage() throws {
        pages += 1
        guard pages <= 1_000 else { throw MigrationCounterPreflight.Failure.notFresh }
    }

    var counts: [String: Int] {
        types.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
