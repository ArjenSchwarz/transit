import SwiftUI

struct ProjectColorDot: View {
    let color: Color
    var size: CGFloat
    var cornerRadius: CGFloat
    var label: String?

    init(
        color: Color,
        size: CGFloat = 14,
        cornerRadius: CGFloat = 4,
        label: String? = nil
    ) {
        self.color = color
        self.size = size
        self.cornerRadius = cornerRadius
        self.label = label
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }

            if let label, !label.isEmpty {
                Text(String(label.prefix(1)).uppercased())
                    .font(.system(size: max(8, size * 0.46), weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        ProjectColorDot(color: .blue)
        ProjectColorDot(color: .green, size: 22, cornerRadius: 6, label: "Transit")
    }
    .padding()
}
