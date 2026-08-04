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

        #expect(lifecycle.beginSave())
        #expect(lifecycle.blocksDismissal)
        #expect(lifecycle.cancelForDisappearance())
        #expect(lifecycle.isCancellationPending)
    }

    @Test func successfulSaveDoesNotCancelWhenDismissalMakesViewDisappear() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        #expect(lifecycle.beginSave())
        #expect(lifecycle.completeSave())
        #expect(lifecycle.blocksDismissal)
        #expect(lifecycle.cancelForDisappearance() == false)
        #expect(lifecycle.isCancellationPending == false)
    }

    @Test func failedSaveReenablesDismissalAndRetry() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        #expect(lifecycle.beginSave())
        lifecycle.completeFailure()

        #expect(lifecycle.blocksDismissal == false)
        #expect(lifecycle.beginSave())
    }

    @Test func completingCancellationReenablesTheEditor() {
        var lifecycle = MilestoneCreateSaveLifecycle()

        #expect(lifecycle.beginSave())
        #expect(lifecycle.cancelForDisappearance())
        lifecycle.completeCancellation()

        #expect(lifecycle.blocksDismissal == false)
        #expect(lifecycle.isCancellationPending == false)
    }
}
