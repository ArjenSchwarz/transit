import AppIntents

enum ReportDateRange: String, AppEnum, CaseIterable, Identifiable {
    case today = "today"
    case yesterday = "yesterday"
    case thisWeek = "this-week"
    case lastWeek = "last-week"
    case thisMonth = "this-month"
    case lastMonth = "last-month"
    case thisYear = "this-year"
    case lastYear = "last-year"

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Date Range")
    }

    nonisolated static var caseDisplayRepresentations: [ReportDateRange: DisplayRepresentation] {
        [
            .today: "Today",
            .yesterday: "Yesterday",
            .thisWeek: "This Week",
            .lastWeek: "Last Week",
            .thisMonth: "This Month",
            .lastMonth: "Last Month",
            .thisYear: "This Year",
            .lastYear: "Last Year"
        ]
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .lastWeek: "Last Week"
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .thisYear: "This Year"
        case .lastYear: "Last Year"
        }
    }

    var dateRange: DateFilterHelpers.DateRange {
        switch self {
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .lastWeek: .lastWeek
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .thisYear: .thisYear
        case .lastYear: .lastYear
        }
    }
}
