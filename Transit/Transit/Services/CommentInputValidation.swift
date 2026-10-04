import Foundation

/// Pure comment inputs shared by macOS automation and service callers.
/// Service mutation and error mapping remain with CommentService.
nonisolated enum CommentInputValidation {
    struct Input: Sendable, Equatable {
        let content: String
        let authorName: String
    }

    enum Error: Swift.Error, Sendable, Equatable {
        case emptyContent
        case emptyAuthorName
    }

    static func normalize(content: String, authorName: String) throws -> Input {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw Error.emptyContent }
        let author = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty else { throw Error.emptyAuthorName }
        return Input(content: content, authorName: author)
    }
}
