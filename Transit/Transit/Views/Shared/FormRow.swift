import SwiftUI

struct FormRow<Content: View>: View {
    let label: String
    let labelWidth: CGFloat
    let content: Content

    init(_ label: String,
         labelWidth: CGFloat,
         @ViewBuilder content: () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content()
    }

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
