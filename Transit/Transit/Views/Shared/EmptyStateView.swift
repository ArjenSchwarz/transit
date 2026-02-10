import SwiftUI

struct EmptyStateView: View {
    let message: String
    var symbol: String

    init(message: String, symbol: String = "tray") {
        self.message = message
        self.symbol = symbol
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyStateView(message: "No tasks in Planning")
        .padding()
}
