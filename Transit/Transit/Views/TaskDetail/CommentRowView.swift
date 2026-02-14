import SwiftUI

struct CommentRowView: View {
    let comment: Comment
    var onDelete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                avatar
                    .frame(width: 20, height: 20)

                Text(comment.authorName)
                    .font(.caption)
                    .fontWeight(.semibold)

                if comment.isAgent {
                    Text("Agent")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.1), in: Capsule())
                }

                Spacer()

                Text(comment.creationDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                #if os(macOS)
                if isHovering, let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }

            Text(comment.content)
                .font(.callout)
                .padding(.leading, 26)
        }
        .padding(.vertical, 6)
        .background(comment.isAgent ? Color.purple.opacity(0.04) : .clear)
        #if os(macOS)
        .onHover { isHovering = $0 }
        #endif
    }

    @ViewBuilder
    private var avatar: some View {
        if comment.isAgent {
            Image(systemName: "cpu")
                .font(.caption2)
                .foregroundStyle(.purple.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(.purple.opacity(0.1), in: Circle())
        } else {
            Text(String(comment.authorName.prefix(1)).uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(width: 20, height: 20)
                .background(.blue.opacity(0.1), in: Circle())
        }
    }
}
