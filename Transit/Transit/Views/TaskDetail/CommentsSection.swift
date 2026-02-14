import SwiftUI

struct CommentsSection: View {
    let task: TransitTask

    @Environment(CommentService.self) private var commentService
    @AppStorage("userDisplayName") private var userDisplayName = ""

    @State private var comments: [Comment] = []
    @State private var newCommentText = ""

    private var trimmedDisplayName: String {
        userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddComment: Bool {
        !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !trimmedDisplayName.isEmpty
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        Section("Comments") {
            if trimmedDisplayName.isEmpty {
                Label(
                    "Set your name in Settings to add comments",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if comments.isEmpty {
                Text("No comments yet")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(comments) { comment in
                    CommentRowView(comment: comment)
                }
                .onDelete { offsets in
                    for index in offsets {
                        deleteComment(comments[index])
                    }
                }
            }

            if !trimmedDisplayName.isEmpty {
                commentInputField
            }
        }
        .onAppear { loadComments() }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        LiquidGlassSection(title: "Comments") {
            VStack(alignment: .leading, spacing: 0) {
                if trimmedDisplayName.isEmpty {
                    Label(
                        "Set your name in Settings to add comments",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                }

                if comments.isEmpty {
                    Text("No comments yet")
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(comments) { comment in
                        CommentRowView(comment: comment, onDelete: {
                            deleteComment(comment)
                        })
                        if comment.id != comments.last?.id {
                            Divider()
                        }
                    }
                }

                if !trimmedDisplayName.isEmpty {
                    Divider().padding(.vertical, 4)
                    commentInputField
                }
            }
        }
        .onAppear { loadComments() }
    }
    #endif

    // MARK: - Comment Input

    private var commentInputField: some View {
        HStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                if newCommentText.isEmpty {
                    Text("Add a comment...")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $newCommentText)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
            }
            Button { addComment() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!canAddComment)
        }
    }

    // MARK: - Actions

    private func loadComments() {
        comments = (try? commentService.fetchComments(for: task.id)) ?? []
    }

    private func addComment() {
        guard canAddComment else { return }
        _ = try? commentService.addComment(
            to: task,
            content: newCommentText,
            authorName: trimmedDisplayName,
            isAgent: false
        )
        newCommentText = ""
        loadComments()
    }

    private func deleteComment(_ comment: Comment) {
        try? commentService.deleteComment(comment)
        loadComments()
    }
}
