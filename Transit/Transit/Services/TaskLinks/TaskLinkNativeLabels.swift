/// Relationship wording is relative to the selected endpoint; raw stored kinds
/// stay in the graph and unknown kinds never acquire a recognized meaning.
nonisolated enum TaskLinkNativeLabels {
    static func title(kind: String, incoming: Bool) -> String {
        switch kind {
        case "dependency": incoming ? "Blocked by" : "Blocks"
        case "association": "Relates to"
        case "attribution": incoming ? "Introduces" : "Introduced by"
        case "duplicate": incoming ? "Duplicated by" : "Duplicate of"
        default: "Unknown relation"
        }
    }
}
