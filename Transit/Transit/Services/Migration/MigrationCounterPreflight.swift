import Foundation

/// No cloud/store implementation here: inspection and preparation are separately callable and fakeable.
@MainActor final class MigrationCounterPreflight {
    nonisolated struct Destination: Codable, Equatable, Sendable {
        let team: String
        let container: String
        let environment: String
        static let release = Destination(team: "4PJS97G236", container: "iCloud.me.nore.ig.apps.Transit",
                                         environment: "Development")
    }
    nonisolated struct Floors: Codable, Equatable, Sendable {
        let tasks: Int
        let milestones: Int
        func validate() throws {
            guard tasks >= 2507, milestones >= 22, tasks < Int.max, milestones < Int.max else {
                throw Failure.invalidFloors
            }
        }
    }
    nonisolated struct Inventory: Equatable, Sendable {
        let account: String
        let counts: [String: Int]
        let unexpectedZones: [String]
        let unexpectedTypes: [String]
        let taskCounter: Int
        let milestoneCounter: Int
        var isFresh: Bool {
            unexpectedZones.isEmpty && unexpectedTypes.isEmpty && counts.allSatisfy {
                ["CDMR", "CD_SyncHeartbeat", "DisplayIDCounter"].contains($0.key) || $0.value == 0
            }
        }
    }
    nonisolated struct Receipt: Codable, Equatable, Sendable {
        let version: Int
        let destination: Destination
        let account: String
        let floors: Floors
    }
    enum Failure: Error, LocalizedError {
        case invalidDestination, invalidFloors, unavailable, notFresh, invalidReceipt, counterReadback, busy
        var errorDescription: String? {
            switch self {
            case .invalidDestination: "The selected signing team, container or cloud environment does not match."
            case .invalidFloors: "Enter task and milestone next-ID floors of at least 2507 and 22."
            case .unavailable: "A durable Release store with iCloud sync active is required."
            case .notFresh: "User records or unknown zones/types prevent fresh preparation."
            case .invalidReceipt: "Readiness belongs to another destination/account, or its saved values are invalid."
            case .counterReadback: "Both cloud counters must verify at or above the floors. Writes remain blocked."
            case .busy: "A readiness operation is already running."
            }
        }
    }
    protocol Cloud {
        func account() async throws -> String
        func inspect() async throws -> Inventory
        func ensureZone() async throws
        var tasks: any DisplayIDAllocator.CounterStore { get }
        var milestones: any DisplayIDAllocator.CounterStore { get }
    }
    let destination: Destination
    private let cloud: any Cloud
    private let enabled: Bool
    private let canPrepareFresh: () throws -> Bool
    private let readReceipt: () throws -> Data?
    private let writeReceipt: (Data) throws -> Void
    private var busy = false
    private(set) var isVerified = false
    private(set) var verifiedFloors: Floors?

    init(destination: Destination, enabled: Bool, cloud: any Cloud,
         canPrepareFresh: @escaping () throws -> Bool = { true },
         readReceipt: @escaping () throws -> Data?, writeReceipt: @escaping (Data) throws -> Void) {
        self.destination = destination
        self.enabled = enabled
        self.canPrepareFresh = canPrepareFresh
        self.cloud = cloud
        self.readReceipt = readReceipt
        self.writeReceipt = writeReceipt
    }

    func inspect() async throws -> Inventory {
        try begin()
        defer { busy = false }
        return try await cloud.inspect()
    }

    /// Existing receipts never authorize offline access: re-read account and both counters every launch.
    func verifySaved() async throws -> Bool {
        try begin()
        defer { busy = false }
        guard let data = try readReceipt() else { return false }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        try receipt.floors.validate()
        guard receipt.version == 1, receipt.destination == destination,
              receipt.account == (try await cloud.account()) else { throw Failure.invalidReceipt }
        let verified = try await verifyCounters(receipt.floors)
        try await requireAccount(receipt.account)
        verifiedFloors = verified
        isVerified = true
        return true
    }

    /// fresh=true performs only increasing counter writes; false adopts already-sufficient counters read-only.
    func prepare(floors: Floors, confirmedContainer: String, fresh: Bool) async throws {
        try begin()
        defer { busy = false }
        try floors.validate()
        guard confirmedContainer == destination.container else { throw Failure.invalidDestination }
        let inventory = try await cloud.inspect()
        guard inventory.unexpectedZones.isEmpty, inventory.unexpectedTypes.isEmpty,
              !fresh || inventory.isFresh else { throw Failure.notFresh }
        if fresh {
            guard try canPrepareFresh() else { throw Failure.notFresh }
            try Task.checkCancellation()
            try await requireAccount(inventory.account)
            try await cloud.ensureZone()
            try await requireAccount(inventory.account)
            try await cloud.tasks.advanceCounter(toAtLeast: floors.tasks)
            try await requireAccount(inventory.account)
            try await cloud.milestones.advanceCounter(toAtLeast: floors.milestones)
        }
        let verified = try await verifyCounters(floors)
        guard try await cloud.account() == inventory.account else { throw Failure.invalidReceipt }
        let receipt = Receipt(version: 1, destination: destination, account: inventory.account, floors: floors)
        try Task.checkCancellation()
        try writeReceipt(JSONEncoder().encode(receipt))
        verifiedFloors = verified
        isVerified = true
    }

    private func begin() throws {
        guard !busy else { throw Failure.busy }
        isVerified = false
        verifiedFloors = nil
        guard enabled else { throw Failure.unavailable }
        guard destination == .release else { throw Failure.invalidDestination }
        busy = true
    }

    private func requireAccount(_ expected: String) async throws {
        try Task.checkCancellation()
        guard try await cloud.account() == expected else { throw Failure.invalidReceipt }
    }

    private func verifyCounters(_ floors: Floors) async throws -> Floors {
        let tasks = try await cloud.tasks.loadCounter()
        let milestones = try await cloud.milestones.loadCounter()
        guard tasks.nextDisplayID >= floors.tasks, milestones.nextDisplayID >= floors.milestones else {
            throw Failure.counterReadback
        }
        return Floors(tasks: tasks.nextDisplayID, milestones: milestones.nextDisplayID)
    }
}
