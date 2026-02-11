import AppIntents

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
