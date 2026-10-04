#if os(macOS)
import Foundation
import Testing
@testable import Transit

extension MCPPortfolioProjectionTests {
    @Test func supportedSnapshotArgumentsDeduplicateStatuses() throws {
        var arguments = args()
        let projectID = UUID()
        arguments["projectId"] = projectID.uuidString
        arguments["status"] = ["idea", "done", "idea"]
        let parsed = try MCPSnapshotTaskQueryRequest.parse(arguments)
        guard case .initial(let id, let detail, let limit, let project, let statuses) = parsed else {
            Issue.record("Initial snapshot query parsed as continuation")
            return
        }
        #expect(id == arguments["snapshotId"] as? String && detail == .summary && limit == 2)
        #expect(project == projectID && Set(statuses) == ["idea", "done"] && statuses.count == 2)
    }

    @Test func omittedAndEmptyStatusArrayHaveNoRestriction() throws {
        for status in [Optional<[String]>.none, []] {
            var arguments = args()
            arguments["status"] = status
            guard case .initial(_, _, _, _, let statuses) = try MCPSnapshotTaskQueryRequest.parse(arguments) else {
                Issue.record("Initial snapshot query parsed as continuation")
                return
            }
            #expect(statuses.isEmpty)
        }
    }

    @Test(arguments: ["snapshotId", "detailLevel", "includeComments", "limit"])
    func requiredFieldsCannotBeOmitted(key: String) {
        var arguments = args()
        arguments.removeValue(forKey: key)
        #expect(throws: MCPSnapshotTaskQueryError.invalidInput) { try MCPSnapshotTaskQueryRequest.parse(arguments) }
    }

    @Test(arguments: ["project", "search", "type", "priority", "unfinished", "not_status",
                      "displayId", "taskIds", "displayIds", "milestone", "milestoneDisplayId", "readPolicy", "unknown"])
    func unsupportedFieldsHaveTypedCompatibilityError(key: String) {
        var arguments = args()
        arguments[key] = "unsupported"
        #expect(throws: MCPSnapshotTaskQueryError.incompatible) { try MCPSnapshotTaskQueryRequest.parse(arguments) }
    }

    @Test func commentBodiesAreExplicitlyUnsupported() {
        var arguments = args()
        arguments["includeComments"] = true
        #expect(throws: MCPSnapshotTaskQueryError.incompatible) { try MCPSnapshotTaskQueryRequest.parse(arguments) }
    }

    @Test func wrongScalarTypesAndMalformedUUIDsFailValidation() {
        let overrides: [(String, Any)] = [
            ("snapshotId", 1), ("snapshotId", "not-a-uuid"), ("snapshotId", NSNull()),
            ("projectId", true), ("projectId", "not-a-uuid"), ("projectId", NSNull()),
            ("detailLevel", "verbose"), ("detailLevel", 1),
            ("includeComments", "false"), ("includeComments", 0), ("includeComments", NSNull()),
            ("limit", true), ("limit", 1.5), ("limit", 0), ("limit", 101), ("limit", "2"),
            ("status", "idea"), ("status", ["unknown"]), ("status", [1]), ("status", NSNull())
        ]
        for (key, value) in overrides {
            var arguments = args()
            arguments[key] = value
            #expect(throws: MCPSnapshotTaskQueryError.invalidInput) {
                try MCPSnapshotTaskQueryRequest.parse(arguments)
            }
        }
    }

    @Test func fullDetailAndJSONIntegralLimitAreSupported() throws {
        var arguments = args()
        arguments["detailLevel"] = "full"
        arguments["limit"] = Double(100)
        guard case .initial(_, let detail, let limit, _, _) = try MCPSnapshotTaskQueryRequest.parse(arguments) else {
            Issue.record("Initial snapshot query parsed as continuation")
            return
        }
        #expect(detail == .full && limit == 100)
    }

    @Test func reusableContinuationPreservesOptionalPolicyAndRejectsOtherFields() throws {
        let cursor = "00000000-0000-8000-8000-000000000001"
        for policy in [Optional<String>.none, "cached", "refresh_if_needed"] {
            var arguments: [String: Any] = ["cursor": cursor]
            arguments["readPolicy"] = policy
            let request = try MCPSnapshotTaskQueryRequest.parse(arguments)
            guard case .continuation(let parsed, let parsedPolicy) = request else {
                Issue.record("Continuation parsed as initial query")
                return
            }
            #expect(parsed == cursor && parsedPolicy?.rawValue == policy)
        }
        #expect(throws: MCPSnapshotTaskQueryError.incompatible) {
            try MCPSnapshotTaskQueryRequest.parse(["cursor": cursor, "limit": 2])
        }
        #expect(throws: MCPSnapshotTaskQueryError.invalidInput) {
            try MCPSnapshotTaskQueryRequest.parse(["cursor": cursor, "readPolicy": "invalid"])
        }
    }

    @Test func reusableParserDoesNotConsumeOrdinaryV4OrUnknownCursorFamilies() {
        for cursor in [UUID().uuidString, "00000000-0000-1000-8000-000000000001", "invalid"] {
            #expect(throws: MCPSnapshotTaskQueryError.invalidCursor) {
                try MCPSnapshotTaskQueryRequest.parse(["cursor": cursor])
            }
        }
        #expect(MCPCursorFamily.classify("00000000-0000-8000-8000-000000000001") == .reusable)
        #expect(MCPCursorFamily.classify(UUID().uuidString) == .ordinary)
    }
}
#endif
