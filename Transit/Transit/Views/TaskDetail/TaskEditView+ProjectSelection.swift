import Foundation
import SwiftUI

extension TaskEditView {

    /// Resolves the picker ID against the observed project models immediately
    /// before Save, because a remote delete can leave the ID behind.
    var projectSelectionState: TaskEditProjectSelectionState {
        TaskEditProjectSelectionState(
            selectedProjectID: selectedProjectID,
            resolvedProjectID: selectedProject?.id
        )
    }

    /// Visible recovery guidance for an intentionally disabled Save control.
    @ViewBuilder
    var projectSelectionRecovery: some View {
        if let message = projectSelectionState.recoveryMessage,
           let label = projectSelectionState.recoveryAccessibilityLabel,
           let hint = projectSelectionState.recoveryAccessibilityHint {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
                .accessibilityHint(hint)
        }
    }

    #if os(macOS)
    @ViewBuilder
    var macOSProjectSelectionRecovery: some View {
        if projectSelectionState.recoveryMessage != nil {
            FormRow("Project error", labelWidth: Self.labelWidth) {
                projectSelectionRecovery
            }
        }
    }
    #endif
}
