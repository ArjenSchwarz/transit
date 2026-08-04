import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1858. The editor must retain and cancel a create
/// operation only while it is truly in flight; a completed save must be allowed
/// to dismiss without its own disappearance being treated as cancellation.
@MainActor
struct MilestoneCreateSaveLifecycleTests {

    @Test func disappearanceDuringInFlightCreateRequestsCancellation() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        let blocksWhileSaving = lifecycle.blocksDismissal
        let didRequestCancellation = lifecycle.cancelForDisappearance()

        #expect(didBegin)
        #expect(blocksWhileSaving)
        #expect(didRequestCancellation)
        #expect(lifecycle.isCancellationPending)
    }

    @Test func successfulSaveDoesNotCancelWhenDismissalMakesViewDisappear() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        let didCompleteSave = lifecycle.completeSave()
        let blocksWhileDismissing = lifecycle.blocksDismissal
        let didRequestCancellation = lifecycle.cancelForDisappearance()

        #expect(didBegin)
        #expect(didCompleteSave)
        #expect(blocksWhileDismissing)
        #expect(didRequestCancellation == false)
        #expect(lifecycle.isCancellationPending == false)
    }

    @Test func failedSaveReenablesDismissalAndRetry() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        lifecycle.completeFailure()
        let blocksAfterFailure = lifecycle.blocksDismissal
        let didRetry = lifecycle.beginSave()

        #expect(didBegin)
        #expect(blocksAfterFailure == false)
        #expect(didRetry)
    }

    @Test func completingCancellationReenablesTheEditor() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        let didRequestCancellation = lifecycle.cancelForDisappearance()
        lifecycle.completeCancellation()

        #expect(didBegin)
        #expect(didRequestCancellation)
        #expect(lifecycle.blocksDismissal == false)
        #expect(lifecycle.isCancellationPending == false)
    }
}
