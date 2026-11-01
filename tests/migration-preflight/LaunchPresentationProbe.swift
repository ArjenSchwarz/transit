import Foundation

extension PreflightProbe {
    @MainActor static func testLaunchPresentation() async throws {
        // This is the view's initial state, before any asynchronous verification can finish.
        precondition(!MigrationLaunchPresentation.checking.showsSetup)
        precondition(MigrationLaunchPresentation.checking.message.isEmpty)
        let cloud = FakeCloud(taskCounter: 2507, milestoneCounter: 22), box = ReceiptBox()
        box.data = try JSONEncoder().encode(MigrationCounterPreflight.Receipt(
            version: 1, destination: .release, account: cloud.identity, floors: .init(tasks: 2507, milestones: 22)))
        let saved = make(cloud, box)
        let success = await MigrationLaunchPresentation.verify(saved)
        precondition(success == .ready && !success.showsSetup && success.message.isEmpty)
        precondition(saved.isVerified && box.writes == 0 && cloud.reads == 0)
        await assertNoCloudWrites(cloud)

        let unpreparedCloud = FakeCloud(), emptyBox = ReceiptBox()
        let unprepared = make(unpreparedCloud, emptyBox)
        let setup = await MigrationLaunchPresentation.verify(unprepared)
        precondition(setup == .needsSetup && setup.showsSetup && !setup.message.isEmpty)
        precondition(!unprepared.isVerified && emptyBox.data == nil)
        await assertNoCloudWrites(unpreparedCloud)

        cloud.identity = "different-account"
        let failed = await MigrationLaunchPresentation.verify(saved)
        guard case .failed(let message) = failed else { preconditionFailure("Account failure hidden") }
        precondition(failed.showsSetup && !message.isEmpty && !saved.isVerified && saved.verifiedFloors == nil)
        precondition(box.writes == 0)
        await assertNoCloudWrites(cloud)
        cloud.identity = "account-A"
        await cloud.taskStore.configure(fail: true)
        let unavailable = await MigrationLaunchPresentation.verify(saved)
        guard case .failed = unavailable else { preconditionFailure("Counter-read failure hidden") }
        precondition(unavailable.showsSetup && !unavailable.message.isEmpty && !saved.isVerified)
        await assertNoCloudWrites(cloud)
        print("Launch presentation passes: quiet pending/success; account, counter and unprepared failures visible")
    }
}
