import Testing
@testable import Transit

@MainActor
struct MilestoneStatusTests {

    // MARK: - isTerminal

    @Test func openIsNotTerminal() {
        #expect(!MilestoneStatus.open.isTerminal)
    }

    @Test func doneIsTerminal() {
        #expect(MilestoneStatus.done.isTerminal)
    }

    @Test func abandonedIsTerminal() {
        #expect(MilestoneStatus.abandoned.isTerminal)
    }

    // MARK: - displayName

    @Test func displayNames() {
        #expect(MilestoneStatus.open.displayName == "Open")
        #expect(MilestoneStatus.done.displayName == "Done")
        #expect(MilestoneStatus.abandoned.displayName == "Abandoned")
    }

    // MARK: - rawValue

    @Test func rawValues() {
        #expect(MilestoneStatus.open.rawValue == "open")
        #expect(MilestoneStatus.done.rawValue == "done")
        #expect(MilestoneStatus.abandoned.rawValue == "abandoned")
    }

    @Test func initFromRawValue() {
        #expect(MilestoneStatus(rawValue: "open") == .open)
        #expect(MilestoneStatus(rawValue: "done") == .done)
        #expect(MilestoneStatus(rawValue: "abandoned") == .abandoned)
        #expect(MilestoneStatus(rawValue: "invalid") == nil)
    }
}
