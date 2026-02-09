import SwiftUI

struct EmptyStateView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(message, systemImage: "tray")
        }
    }
}
