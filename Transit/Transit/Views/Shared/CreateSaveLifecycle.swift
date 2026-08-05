/// Models an asynchronous creation save from start through either cancellation,
/// failure, or a successful dismissal.
///
/// A successful save transitions before `dismiss()` so its resulting
/// `onDisappear` cannot cancel data that has already persisted. A view that
/// disappears during a pending create instead transitions to cancellation,
/// allowing the service's persistence-boundary cancellation checks to prevent
/// a ghost record.
nonisolated struct CreateSaveLifecycle: Equatable {
    private enum State: Equatable {
        case idle
        case saving
        case cancellationPending
        case savedAwaitingDismissal
    }

    private var state: State = .idle

    /// Keeps navigation and interactive dismissal unavailable until either a
    /// save error/cancellation returns the editor to idle or the save dismisses it.
    var blocksDismissal: Bool {
        switch state {
        case .saving, .savedAwaitingDismissal:
            true
        case .idle, .cancellationPending:
            false
        }
    }

    var isCancellationPending: Bool {
        state == .cancellationPending
    }

    /// Starts one create operation. Repeated save actions are ignored while the
    /// current operation owns the lifecycle.
    mutating func beginSave() -> Bool {
        guard state == .idle else { return false }
        state = .saving
        return true
    }

    /// Marks a still-pending create for cancellation when its view disappears.
    /// A completed save intentionally returns false so its own `dismiss()` does
    /// not cancel the operation after persistence has succeeded.
    mutating func cancelForDisappearance() -> Bool {
        guard state == .saving else { return false }
        state = .cancellationPending
        return true
    }

    /// Records persistence success before the view is dismissed.
    mutating func completeSave() -> Bool {
        guard state == .saving else { return false }
        state = .savedAwaitingDismissal
        return true
    }

    /// Prepares a reusable view for its next presentation after its previous
    /// successful save dismissed it. A cancellation still owns its task handle
    /// until it settles, so this deliberately leaves other states unchanged.
    mutating func resetAfterSuccessfulDismissal() {
        guard state == .savedAwaitingDismissal else { return }
        state = .idle
    }

    mutating func completeFailure() {
        guard state == .saving else { return }
        state = .idle
    }

    mutating func completeCancellation() {
        guard state == .saving || state == .cancellationPending else { return }
        state = .idle
    }
}
