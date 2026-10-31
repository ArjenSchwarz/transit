import Foundation

actor FakeCounter: DisplayIDAllocator.CounterStore {
    var value: Int
    var writes = 0
    var conflicts = 0
    var fail = false
    var ignoreWrites = false
    init(_ value: Int = 1) { self.value = value }
    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        if fail { throw ProbeFailure.injected }
        return .init(nextDisplayID: value, changeTag: String(value))
    }
    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        if fail { throw ProbeFailure.injected }
        if conflicts > 0 { conflicts -= 1; throw DisplayIDAllocator.Error.conflict }
        precondition(expectedChangeTag == String(value))
        precondition(nextDisplayID >= value)
        writes += 1
        if !ignoreWrites { value = nextDisplayID }
    }
    func configure(fail: Bool = false, ignoreWrites: Bool = false, conflicts: Int = 0) {
        self.fail = fail
        self.ignoreWrites = ignoreWrites
        self.conflicts = conflicts
    }
}
enum ProbeFailure: Error { case injected }
@MainActor final class FakeCloud: MigrationCounterPreflight.Cloud {
    let taskStore = FakeCounter()
    let milestoneStore = FakeCounter()
    var tasks: any DisplayIDAllocator.CounterStore { taskStore }
    var milestones: any DisplayIDAllocator.CounterStore { milestoneStore }
    var identity = "account-A"
    var accountReads = 0
    var switchAccountAt: Int?
    var pause = false
    var continuation: CheckedContinuation<Void, Never>?
    var reads = 0
    var zoneWrites = 0
    var counts: [String: Int] = [:]
    var zones: [String] = []
    var types: [String] = []
    func account() async throws -> String {
        accountReads += 1
        if accountReads == switchAccountAt { identity = "account-B" }
        return identity
    }
    func inspect() async throws -> MigrationCounterPreflight.Inventory {
        reads += 1
        if pause { await withCheckedContinuation { continuation = $0 }; pause = false }
        return .init(account: identity, counts: counts, unexpectedZones: zones, unexpectedTypes: types,
                     taskCounter: 1, milestoneCounter: 1)
    }
    func ensureZone() async throws { zoneWrites += 1 }
}
@MainActor final class ReceiptBox {
    var data: Data?
    var fail = false
    func save(_ data: Data) throws {
        if fail { throw ProbeFailure.injected }
        self.data = data
    }
}
@main struct PreflightProbe {
    @MainActor static func main() async throws {
        try await testHappyAndReceipt()
        try await testFailures()
        try await testInputAndDestination()
        try await testSingleFlightAndLocalGraph()
        try testPaginationAndWriteGate()
        print("Migration preflight fake checks passed: CAS, readback, partial failure, account and write gates")
    }
    @MainActor static func make(
        _ cloud: FakeCloud, _ box: ReceiptBox, enabled: Bool = true,
        destination: MigrationCounterPreflight.Destination = .release
    ) -> MigrationCounterPreflight {
        MigrationCounterPreflight(destination: destination, enabled: enabled, cloud: cloud,
                                  readReceipt: { box.data }, writeReceipt: { try box.save($0) })
    }
    @MainActor static func prepare(_ preflight: MigrationCounterPreflight, fresh: Bool = true) async throws {
        try await preflight.prepare(
            floors: .init(tasks: 2507, milestones: 22),
            confirmedContainer: MigrationCounterPreflight.Destination.release.container, fresh: fresh)
    }
    @MainActor static func rejects(_ operation: () async throws -> Void) async {
        do { try await operation(); preconditionFailure("Unsafe operation succeeded") } catch {}
    }
    @MainActor static func testHappyAndReceipt() async throws {
        let cloud = FakeCloud(), box = ReceiptBox()
        let preflight = make(cloud, box)
        _ = try await preflight.inspect()
        precondition(cloud.zoneWrites == 0 && !preflight.isVerified && box.data == nil)
        let initialWrites = await cloud.taskStore.writes
        precondition(initialWrites == 0)
        await cloud.taskStore.configure(conflicts: 2)
        try await prepare(preflight)
        precondition(preflight.isVerified && box.data != nil)
        let taskValue = try await cloud.tasks.loadCounter().nextDisplayID
        let milestoneValue = try await cloud.milestones.loadCounter().nextDisplayID
        precondition(taskValue == 2507 && milestoneValue == 22)
        try await cloud.tasks.advanceCounter(toAtLeast: 3000)
        let writes = await cloud.taskStore.writes
        let follower = make(cloud, box)
        let verified = try await follower.verifySaved()
        precondition(verified && follower.isVerified && follower.verifiedFloors?.tasks == 3000)
        cloud.counts = ["CD_Project": 1]
        try await prepare(follower, fresh: false)
        let afterWrites = await cloud.taskStore.writes
        precondition(afterWrites == writes)
        cloud.identity = "account-B"
        await rejects { _ = try await follower.verifySaved() }
        precondition(!follower.isVerified)
        cloud.identity = "account-A"
        box.data = try JSONEncoder().encode(MigrationCounterPreflight.Receipt(
            version: 99, destination: .release, account: cloud.identity, floors: .init(tasks: 2507, milestones: 22)))
        await rejects { _ = try await follower.verifySaved() }
        box.data = try JSONEncoder().encode(MigrationCounterPreflight.Receipt(
            version: 1, destination: .release, account: cloud.identity, floors: .init(tasks: 1, milestones: 1)))
        await rejects { _ = try await follower.verifySaved() }
        box.data = Data("invalid receipt".utf8)
        await rejects { _ = try await follower.verifySaved() }
    }
    @MainActor static func testFailures() async throws {
        let cloud = FakeCloud(), box = ReceiptBox()
        let preflight = make(cloud, box)
        cloud.counts = ["CD_Project": 1]
        await rejects { try await prepare(preflight) }
        precondition(cloud.zoneWrites == 0 && box.data == nil && !preflight.isVerified)
        cloud.counts = [:]
        cloud.zones = ["unexpected"]
        await rejects { try await prepare(preflight) }
        cloud.zones = []; cloud.types = ["unknown"]
        await rejects { try await prepare(preflight) }
        cloud.types = []
        await cloud.milestoneStore.configure(fail: true)
        await rejects { try await prepare(preflight) }
        let value = try await cloud.tasks.loadCounter().nextDisplayID
        precondition(value == 2507 && box.data == nil && !preflight.isVerified)
        await cloud.milestoneStore.configure(ignoreWrites: true)
        await rejects { try await prepare(preflight) }
        precondition(box.data == nil && !preflight.isVerified)
        await cloud.milestoneStore.configure()
        box.fail = true
        await rejects { try await prepare(preflight) }
        precondition(!preflight.isVerified)
        box.fail = false
        try await prepare(preflight)
        await cloud.taskStore.configure(fail: true)
        await rejects { _ = try await preflight.verifySaved() }
        precondition(!preflight.isVerified)
    }
    @MainActor static func testInputAndDestination() async throws {
        let cloud = FakeCloud(), box = ReceiptBox()
        let disabled = make(cloud, box, enabled: false)
        await rejects { _ = try await disabled.inspect() }
        let wrong = make(cloud, box, destination: .init(team: "other", container: "old", environment: "Production"))
        await rejects { try await prepare(wrong) }
        let preflight = make(cloud, box)
        await rejects {
            try await preflight.prepare(floors: .init(tasks: 2506, milestones: 21),
                                        confirmedContainer: preflight.destination.container, fresh: true)
        }
        await rejects {
            try await preflight.prepare(floors: .init(tasks: 2507, milestones: 22),
                                        confirmedContainer: "old", fresh: true)
        }
        await rejects { try await prepare(preflight, fresh: false) }
        precondition(cloud.zoneWrites == 0 && box.data == nil && !preflight.isVerified)
        let higher = FakeCounter(5000)
        try await higher.advanceCounter(toAtLeast: 2507)
        let writes = await higher.writes
        precondition(writes == 0)
        await cloud.taskStore.configure(conflicts: 10)
        await rejects { try await prepare(preflight) }
        precondition(!preflight.isVerified && box.data == nil)
    }
    @MainActor static func testSingleFlightAndLocalGraph() async throws {
        let cloud = FakeCloud(), box = ReceiptBox()
        let local = MigrationCounterPreflight(destination: .release, enabled: true, cloud: cloud,
            canPrepareFresh: { false }, readReceipt: { nil }, writeReceipt: { try box.save($0) })
        await rejects { try await prepare(local) }
        precondition(cloud.zoneWrites == 0 && box.data == nil)
        let preflight = make(cloud, box)
        cloud.pause = true
        let first = Task { try await prepare(preflight) }
        while cloud.continuation == nil { await Task.yield() }
        await rejects { _ = try await preflight.inspect() }
        precondition(!preflight.isVerified)
        cloud.continuation?.resume()
        try await first.value
        precondition(preflight.isVerified)
        let changed = FakeCloud(), changedBox = ReceiptBox()
        changed.switchAccountAt = 3
        let switched = make(changed, changedBox)
        await rejects { try await prepare(switched) }
        let task = try await changed.tasks.loadCounter().nextDisplayID
        let milestone = try await changed.milestones.loadCounter().nextDisplayID
        precondition(task == 2507 && milestone == 1 && changedBox.data == nil && !switched.isVerified)
    }

    @MainActor static func testPaginationAndWriteGate() throws {
        let gate = PersistenceAvailability()
        gate.setMigrationVerificationRequired(true)
        precondition(gate.areWritesUnavailable)
        gate.setMigrationVerificationRequired(false)
        precondition(!gate.areWritesUnavailable)
        gate.migrationCounterFloors = (tasks: 2507, milestones: 22)
        precondition(gate.permitsImportedDisplayIDs(taskMax: 2506, milestoneMax: 12))
        precondition(!gate.permitsImportedDisplayIDs(taskMax: 2507, milestoneMax: 12))
        precondition(!gate.permitsImportedDisplayIDs(taskMax: 2506, milestoneMax: 22))
        gate.requireRestartAfterReplacement()
        gate.setMigrationVerificationRequired(false)
        precondition(gate.areWritesUnavailable)
        var inventory = MigrationInventoryAccumulator()
        try inventory.record(id: "physical-1", type: "CD_Project", counter: nil)
        try inventory.finishPage()
        try inventory.record(id: "physical-2", type: "CD_Project", counter: nil)
        try inventory.record(id: "global-counter", type: "DisplayIDCounter", counter: 3000)
        inventory.delete(id: "physical-1")
        try inventory.finishPage()
        precondition(inventory.counts["CD_Project"] == 1 && inventory.counters["global-counter"] == 3000)
        inventory.delete(id: "global-counter")
        precondition(inventory.counters.isEmpty)
        do {
            try inventory.record(id: "unexpected-counter", type: "DisplayIDCounter", counter: 2)
            preconditionFailure("Unknown counter accepted")
        } catch {}
        for _ in 0..<998 { try inventory.finishPage() }
        do { try inventory.finishPage(); preconditionFailure("Incomplete/unbounded pagination accepted") } catch {}
    }

}
