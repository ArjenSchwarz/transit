#if os(macOS)
import Foundation

extension MCPReadProjection {
    /// Preserve identifier ambiguity before filters; only uniquely selected batch records need bodies.
    static func taskBodyKeys(_ values: [ReadTaskSelectionValue], request: MCPTaskQueryRequest,
                             filters: MCPQueryFilters?) throws -> Set<LocalRecordKey> {
        switch request.selector {
        case .taskIDs(let ids):
            let wanted = Set(ids.compactMap(UUID.init(uuidString:)))
            let groups = Dictionary(grouping: values.filter { wanted.contains($0.id) }, by: \.id)
            return Set(groups.values.filter { $0.count == 1 }.compactMap { $0.first?.physicalKey })
        case .displayIDs(let ids):
            let wanted = Set(ids)
            let groups = Dictionary(grouping: values.filter {
                $0.permanentDisplayId.map { wanted.contains($0) } == true
            }, by: \.permanentDisplayId)
            return Set(groups.values.filter { $0.count == 1 }.compactMap { $0.first?.physicalKey })
        case .single(let id):
            guard let filters else { return [] }
            let candidates = values.filter { $0.permanentDisplayId == id }
            guard candidates.count <= 1 else {
                throw MCPTaskQueryError(code: "AMBIGUOUS_TASK_ID",
                    message: "Duplicate task identifier detected for displayId \(id)")
            }
            return Set(candidates.filter { matches($0, filters: filters) }.map(\.physicalKey))
        case .list:
            guard let filters else { return [] }
            return Set(values.filter { matches($0, filters: filters) }.map(\.physicalKey))
        }
    }
    static func milestoneBodyKeys(_ values: [ReadMilestoneSelectionValue], arguments: [String: Any],
                                  projectID: UUID?) throws -> Set<LocalRecordKey> {
        let id = IntentHelpers.parseIntValue(arguments["displayId"])
        let candidates = values.filter { id == nil || $0.identity.permanentDisplayId == id }
        if let id, candidates.count > 1 {
            throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                message: "Duplicate milestone identifier detected for displayId \(id)")
        }
        return Set(candidates.filter {
            matchesMilestone($0.identity, arguments: arguments, projectID: projectID)
        }.map(\.physicalKey))
    }
}
#endif
