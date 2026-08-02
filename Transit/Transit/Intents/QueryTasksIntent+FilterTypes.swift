import Foundation

struct DateRangeFilter: Codable {
    var relative: String?
    var from: String?
    var toDate: String?
    /// Set from the raw JSON object before Codable erases whether it was empty.
    var isEmptyObject = false

    enum CodingKeys: String, CodingKey {
        case relative
        case from
        case toDate = "to"
    }

    init(relative: String? = nil, from: String? = nil, toDate: String? = nil) {
        self.relative = relative
        self.from = from
        self.toDate = toDate
    }
}

struct QueryFilters: Codable {
    var displayId: Int?
    var status: String?
    var type: String?
    var priority: String?
    var projectId: String?
    var search: String?
    var completionDate: DateRangeFilter?
    var lastStatusChangeDate: DateRangeFilter?
    var milestone: String?
    var milestoneDisplayId: Int?

    init(
        displayId: Int? = nil,
        status: String? = nil,
        type: String? = nil,
        priority: String? = nil,
        projectId: String? = nil,
        search: String? = nil,
        completionDate: DateRangeFilter? = nil,
        lastStatusChangeDate: DateRangeFilter? = nil,
        milestone: String? = nil,
        milestoneDisplayId: Int? = nil
    ) {
        self.displayId = displayId
        self.status = status
        self.type = type
        self.priority = priority
        self.projectId = projectId
        self.search = search
        self.completionDate = completionDate
        self.lastStatusChangeDate = lastStatusChangeDate
        self.milestone = milestone
        self.milestoneDisplayId = milestoneDisplayId
    }
}
