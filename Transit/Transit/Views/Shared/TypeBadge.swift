import SwiftUI

extension TaskType {
    nonisolated var badgeTitle: String {
        switch self {
        case .bug:
            return "Bug"
        case .feature:
            return "Feature"
        case .chore:
            return "Chore"
        case .research:
            return "Research"
        case .documentation:
            return "Docs"
        }
    }

    nonisolated var badgeTintHex: String {
        switch self {
        case .bug:
            return "C2410C"
        case .feature:
            return "005BC5"
        case .chore:
            return "4A4A4A"
        case .research:
            return "7A3E9D"
        case .documentation:
            return "0B7A57"
        }
    }

    @MainActor
    var badgeTint: Color {
        Color(hex: badgeTintHex)
    }
}

struct TypeBadge: View {
    let type: TaskType

    var body: some View {
        Text(type.badgeTitle)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(type.badgeTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(type.badgeTint.opacity(0.16), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(type.badgeTint.opacity(0.4), lineWidth: 0.8)
            }
            .accessibilityLabel("\(type.badgeTitle) type")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        TypeBadge(type: .bug)
        TypeBadge(type: .feature)
        TypeBadge(type: .research)
    }
    .padding()
}
