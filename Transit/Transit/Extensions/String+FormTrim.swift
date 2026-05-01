import Foundation

extension String {
    /// Trim leading/trailing whitespace and newlines, used by task and milestone form views.
    ///
    /// The form views previously trimmed only `.whitespaces`, which left newline characters
    /// in pasted content (T-1063). Centralising the trim character set here keeps form input
    /// normalisation consistent with the App Intent, MCP, and service layers, all of which
    /// already use `.whitespacesAndNewlines`.
    func trimmedForFormInput() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
