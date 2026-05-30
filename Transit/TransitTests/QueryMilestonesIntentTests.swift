import Foundation
import SwiftData
import Testing
@testable import Transit

// swiftlint:disable file_length
// swiftlint:disable type_body_length
@MainActor @Suite(.serialized)
struct QueryMilestonesIntentTests {

    // MARK: - Helpers

    private struct Services {
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeMilestone(
        in context: ModelContext,
        name: String,
        project: Project,
        displayId: Int,
        status: MilestoneStatus = .open
    ) -> Milestone {
        let milestone = Milestone(name: name, description: nil, project: project, displayID: .permanent(displayId))
        if status != .open {
            milestone.statusRawValue = status.rawValue
            milestone.lastStatusChangeDate = Date.now
            if status.isTerminal {
                milestone.completionDate = Date.now
            }
        }
        context.insert(milestone)
        return milestone
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Success Cases

    @Test func emptyInputReturnsAllMilestones() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "", milestoneService: svc.milestone, projectService: svc.project        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
    }

    @Test func filterByDisplayIdReturnsSingleMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "v1.0")
        // Single lookup includes tasks array
        #expect(parsed.first?["tasks"] is [[String: Any]])
    }

    @Test func filterByProjectReturnsMatchingMilestones() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)
        makeMilestone(in: svc.context, name: "v1.0", project: beta, displayId: 2)

        let result = QueryMilestonesIntent.execute(
            input: "{\"project\":\"Alpha\"}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["projectName"] as? String == "Alpha")
    }

    @Test func filterByStatusReturnsMatchingMilestones() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .done)
        makeMilestone(in: svc.context, name: "v2.0", project: project, displayId: 2, status: .open)

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":\"open\"}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "v2.0")
    }

    @Test func filterBySearchMatchesNameAndDescription() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let alphaRelease = Milestone(
            name: "Alpha Release", description: "First release",
            project: project, displayID: .permanent(1)
        )
        svc.context.insert(alphaRelease)
        let betaMilestone = Milestone(
            name: "Beta", description: "Second alpha attempt",
            project: project, displayID: .permanent(2)
        )
        svc.context.insert(betaMilestone)
        makeMilestone(in: svc.context, name: "Gamma", project: project, displayId: 3)

        let result = QueryMilestonesIntent.execute(
            input: "{\"search\":\"alpha\"}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
    }

    @Test func unknownDisplayIdReturnsEmptyArray() throws {
        let svc = try makeServices()

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":999}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // MARK: - Error Cases

    // T-665: Invalid projectId UUID should return an INVALID_INPUT error, not silently drop the filter
    @Test func invalidProjectIdReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"projectId\":\"not-a-uuid\"}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    @Test func fractionalDisplayIdReturnsInvalidInput() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        // 1.9 should NOT silently truncate to 1
        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1.9}", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("integer") == true)
    }

    @Test func malformedJSONReturnsInvalidInput() throws {
        let svc = try makeServices()

        let result = QueryMilestonesIntent.execute(
            input: "not json", milestoneService: svc.milestone,
            projectService: svc.project        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // T-788: Non-string projectId should return INVALID_INPUT, not silently drop the filter
    @Test func numericProjectIdReturnsInvalidInput() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)

        // Decoy project name must not be used as a fallback when projectId is numeric.
        let result = QueryMilestonesIntent.execute(
            input: "{\"projectId\":123,\"project\":\"Alpha\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    @Test func numericProjectIdWithoutFallbackReturnsInvalidInput() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)

        // No project name fallback — numeric projectId still must be rejected,
        // not treated as a missing filter that returns all milestones.
        let result = QueryMilestonesIntent.execute(
            input: "{\"projectId\":123}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    // MARK: - T-963: displayId lookup must apply remaining filters conjunctively

    // T-963: displayId + non-matching status should return empty array, not the milestone.
    @Test func displayIdWithNonMatchingStatusReturnsEmpty() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .open)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"status\":\"done\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // T-963: displayId + matching status should still return the milestone with detailed output.
    @Test func displayIdWithMatchingStatusReturnsMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1, status: .done)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"status\":\"done\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "v1.0")
        // Detailed lookup still includes tasks array
        #expect(parsed.first?["tasks"] is [[String: Any]])
    }

    // T-963: displayId + non-matching project name should return empty array.
    @Test func displayIdWithNonMatchingProjectReturnsEmpty() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"project\":\"Beta\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // T-963: displayId + matching project name should return the milestone.
    @Test func displayIdWithMatchingProjectReturnsMilestone() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"project\":\"Alpha\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["projectName"] as? String == "Alpha")
    }

    // T-963: displayId + non-matching projectId UUID should return empty array.
    @Test func displayIdWithNonMatchingProjectIdReturnsEmpty() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"projectId\":\"\(beta.id.uuidString)\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // T-963: displayId + matching projectId UUID should return the milestone.
    @Test func displayIdWithMatchingProjectIdReturnsMilestone() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        makeMilestone(in: svc.context, name: "v1.0", project: alpha, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"projectId\":\"\(alpha.id.uuidString)\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["projectName"] as? String == "Alpha")
    }

    // T-963: displayId + non-matching search should return empty array.
    @Test func displayIdWithNonMatchingSearchReturnsEmpty() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"search\":\"nonexistent\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // T-963: displayId + matching search should return the milestone.
    @Test func displayIdWithMatchingSearchReturnsMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"search\":\"v1\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
    }

    // T-963: displayId + invalid status string must return INVALID_STATUS, not bypass validation.
    @Test func displayIdWithInvalidStatusReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"status\":\"invalid\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    // T-963: displayId + non-string status must return INVALID_STATUS, not bypass validation.
    @Test func displayIdWithNonStringStatusReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"status\":123}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    // T-963: displayId + malformed projectId must return INVALID_INPUT, not bypass validation.
    @Test func displayIdWithMalformedProjectIdReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"projectId\":\"not-a-uuid\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    // T-963: displayId + non-string projectId must return INVALID_INPUT, not bypass validation.
    @Test func displayIdWithNumericProjectIdReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":1,\"projectId\":123}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    // T-1280: A JSON boolean displayId must be rejected with INVALID_INPUT, not coerced
    // to 1/0 and silently targeting M-1/M-0. `JSONSerialization` delivers `true`/`false`
    // as `NSNumber(CFBoolean)`, which satisfies `as? Int`; the fix routes parsing through
    // `IntentHelpers.parseIntValue`, which rejects CFBoolean.
    @Test func booleanDisplayIdTrueReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":true}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("displayId must be an integer") == true)
    }

    // T-1280: `false` must be rejected too (it would otherwise coerce to displayId 0).
    @Test func booleanDisplayIdFalseReturnsError() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let result = QueryMilestonesIntent.execute(
            input: "{\"displayId\":false}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("displayId must be an integer") == true)
    }
}
// swiftlint:enable type_body_length
