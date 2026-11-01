import Foundation

extension PreflightProbe {
    @MainActor static func assertNoCloudWrites(_ cloud: FakeCloud) async {
        let tasks = await cloud.taskStore.writes
        let milestones = await cloud.milestoneStore.writes
        precondition(tasks == 0 && milestones == 0 && cloud.zoneWrites == 0)
    }

    @MainActor static func testAutomaticFollowerAdoption() async throws {
        let cloud = FakeCloud(taskCounter: 3000, milestoneCounter: 40), box = ReceiptBox()
        cloud.counts = ["CD_Project": 24, "CD_TransitTask": 2492, "DisplayIDCounter": 2]
        let follower = make(cloud, box)
        let verified = try await follower.verifySaved()
        precondition(verified && follower.isVerified && box.writes == 1)
        precondition(follower.verifiedFloors == .init(tasks: 3000, milestones: 40))
        let data = try requireReceipt(box)
        let receipt = try JSONDecoder().decode(MigrationCounterPreflight.Receipt.self, from: data)
        precondition(receipt.destination == .release && receipt.account == cloud.identity)
        precondition(receipt.floors == .init(tasks: 2507, milestones: 22))
        let reverified = try await follower.verifySaved()
        precondition(reverified && cloud.reads == 1 && box.writes == 1)
        await assertNoCloudWrites(cloud)
        print("Automatic follower adoption passes: prepared destination, local receipt only, saved re-verification")
    }

    @MainActor private static func requireReceipt(_ box: ReceiptBox) throws -> Data {
        guard let data = box.data else { throw ProbeFailure.injected }
        return data
    }

    @MainActor static func testAutomaticFollowerFailures() async throws {
        try await testUnpreparedFollowerCounters()
        await testFollowerVerificationErrors()
        try await testFollowerIdentityMismatch()
        print("Automatic follower failure checks pass: missing/partial counters, identity/errors and zero cloud writes")
    }

    @MainActor private static func testUnpreparedFollowerCounters() async throws {
        for (task, milestone) in [(1, 1), (1, 22), (2507, 1), (2506, 22), (2507, 21)] {
            let cloud = FakeCloud(taskCounter: task, milestoneCounter: milestone), box = ReceiptBox()
            let follower = make(cloud, box)
            let verified = try await follower.verifySaved()
            precondition(!verified && !follower.isVerified && follower.verifiedFloors == nil)
            precondition(box.data == nil && box.writes == 0)
            await assertNoCloudWrites(cloud)
        }
    }

    @MainActor private static func testFollowerVerificationErrors() async {
        for scenario in 0..<7 {
            let cloud = FakeCloud(taskCounter: 2507, milestoneCounter: scenario == 6 ? 21 : 22), box = ReceiptBox()
            switch scenario {
            case 0: cloud.switchAccountAt = 1
            case 1: cloud.zones = ["unexpected-zone"]
            case 2: cloud.types = ["unknown-record-type"]
            case 3: cloud.failInspection = true
            case 4: await cloud.taskStore.configure(fail: true)
            case 5: box.fail = true
            default: cloud.inventoryFloorOverride = (tasks: 2507, milestones: 22)
            }
            let before = box.data
            let follower = make(cloud, box)
            await rejects { _ = try await follower.verifySaved() }
            precondition(!follower.isVerified && follower.verifiedFloors == nil)
            precondition(box.data == before && box.writes == 0)
            await assertNoCloudWrites(cloud)
        }
    }

    @MainActor private static func testFollowerIdentityMismatch() async throws {
        let cloud = FakeCloud(taskCounter: 2507, milestoneCounter: 22), box = ReceiptBox()
        box.data = try JSONEncoder().encode(MigrationCounterPreflight.Receipt(
            version: 1, destination: .release, account: "different-account",
            floors: .init(tasks: 2507, milestones: 22)))
        let mismatchedAccount = make(cloud, box)
        let originalReceipt = box.data
        await rejects { _ = try await mismatchedAccount.verifySaved() }
        precondition(cloud.reads == 0 && box.data == originalReceipt && box.writes == 0)
        precondition(!mismatchedAccount.isVerified)
        box.data = nil
        let wrong = MigrationCounterPreflight.Destination(team: "other", container: "old", environment: "Production")
        let follower = make(cloud, box, destination: wrong)
        await rejects { _ = try await follower.verifySaved() }
        precondition(cloud.reads == 0 && box.data == nil && !follower.isVerified)
        let receipt = MigrationCounterPreflight.Receipt(
            version: 1, destination: wrong, account: cloud.identity, floors: .init(tasks: 2507, milestones: 22))
        box.data = try JSONEncoder().encode(receipt)
        let validDestination = make(cloud, box)
        await rejects { _ = try await validDestination.verifySaved() }
        precondition(cloud.reads == 0 && box.writes == 0 && !validDestination.isVerified)
        await assertNoCloudWrites(cloud)
    }
}
