import AppIntents

/// Date filter options for visual Shortcuts intents.
/// Used in FindTasksIntent for completion date and last status change date filtering.
enum DateFilterOption: String, AppEnum {
    case today
    case thisWeek = "this-week"
    case thisMonth = "this-month"
    case customRange = "custom-range"

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Date Filter")
    }

    nonisolated static var caseDisplayRepresentations: [DateFilterOption: DisplayRepresentation] {
        [
            .today: "Today",
            .thisWeek: "This Week",
            .thisMonth: "This Month",
            .customRange: "Custom Range"
        ]
    }
}
