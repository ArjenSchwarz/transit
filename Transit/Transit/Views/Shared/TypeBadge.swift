import SwiftUI

struct TypeBadge: View {
    let type: TaskType

    var body: some View {
        Text(type.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(type.tintColor.opacity(0.15))
            .foregroundStyle(type.tintColor)
            .clipShape(Capsule())
    }
}
