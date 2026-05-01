import Foundation
import Testing
@testable import Transit

@MainActor
struct DisplayIDMaintenanceTypesTests {

    // MARK: - FailureCode raw strings

    @Test func failureCodeRawValuesMatchDesignTable() {
        #expect(FailureCode.allocationFailed.rawValue == "allocation-failed")
        #expect(FailureCode.saveFailed.rawValue == "save-failed")
        #expect(FailureCode.staleId.rawValue == "stale-id")
        #expect(FailureCode.commentFailed.rawValue == "comment-failed")
        #expect(FailureCode.counterAdvanceFailed.rawValue == "counter-advance-failed")
    }

    // MARK: - DuplicateReport encoding

    @Test func duplicateReportEmptyEncodesAsEmptyArrays() throws {
        let report = DuplicateReport(tasks: [], milestones: [])
        let json = try encodeToJSONObject(report)

        #expect(json["tasks"] is [Any])
        #expect((json["tasks"] as? [Any])?.isEmpty == true)
        #expect((json["milestones"] as? [Any])?.isEmpty == true)
    }

    @Test func duplicateReportRecordRefIncludesAllFields() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let ref = RecordRef(
            id: id, name: "Task A", projectName: "Prism",
            creationDate: date, role: .winner
        )
        let group = DuplicateGroup(displayId: 5, records: [ref])
        let report = DuplicateReport(tasks: [group], milestones: [])
        let json = try encodeToJSONObject(report)

        let tasksArr = try #require(json["tasks"] as? [[String: Any]])
        let firstGroup = try #require(tasksArr.first)
        #expect(firstGroup["displayId"] as? Int == 5)
        let recordsArr = try #require(firstGroup["records"] as? [[String: Any]])
        let recordDict = try #require(recordsArr.first)
        #expect(recordDict["id"] as? String == id.uuidString)
        #expect(recordDict["name"] as? String == "Task A")
        #expect(recordDict["projectName"] as? String == "Prism")
        #expect(recordDict["role"] as? String == "winner")
        let creationDateString = try #require(recordDict["creationDate"] as? String)
        #expect(creationDateString.contains("2023"))
    }

    @Test func recordRefProjectNameNoProjectLiteralWhenNil() throws {
        let ref = RecordRef(
            id: UUID(), name: "Orphan", projectName: "(no project)",
            creationDate: Date(), role: .loser
        )
        let json = try encodeToJSONObject(ref)
        #expect(json["projectName"] as? String == "(no project)")
        #expect(json["role"] as? String == "loser")
    }

    @Test func duplicateReportWinnerFirstOrderingPreserved() throws {
        let winner = RecordRef(
            id: UUID(), name: "Winner", projectName: "P",
            creationDate: Date(), role: .winner
        )
        let loser1 = RecordRef(
            id: UUID(), name: "Loser1", projectName: "P",
            creationDate: Date(), role: .loser
        )
        let loser2 = RecordRef(
            id: UUID(), name: "Loser2", projectName: "P",
            creationDate: Date(), role: .loser
        )
        let group = DuplicateGroup(displayId: 1, records: [winner, loser1, loser2])
        let report = DuplicateReport(tasks: [group], milestones: [])
        let json = try encodeToJSONObject(report)

        let tasksArr = try #require(json["tasks"] as? [[String: Any]])
        let records = try #require(tasksArr.first?["records"] as? [[String: Any]])
        #expect(records.count == 3)
        #expect(records[0]["role"] as? String == "winner")
        #expect(records[1]["role"] as? String == "loser")
        #expect(records[2]["role"] as? String == "loser")
        #expect(records[0]["name"] as? String == "Winner")
        #expect(records[1]["name"] as? String == "Loser1")
        #expect(records[2]["name"] as? String == "Loser2")
    }

    @Test func duplicateReportGroupsOrderedByAscendingDisplayId() throws {
        let groupA = DuplicateGroup(displayId: 7, records: [])
        let groupB = DuplicateGroup(displayId: 2, records: [])
        let groupC = DuplicateGroup(displayId: 5, records: [])
        // The encoder should preserve the order callers provide (which is
        // ascending displayId). We assert encoding round-trip preserves order.
        let report = DuplicateReport(tasks: [groupB, groupC, groupA], milestones: [])
        let json = try encodeToJSONObject(report)
        let tasksArr = try #require(json["tasks"] as? [[String: Any]])
        let displayIds = tasksArr.compactMap { $0["displayId"] as? Int }
        #expect(displayIds == [2, 5, 7])
    }

    // MARK: - ReassignmentResult encoding

    @Test func reassignmentResultOkVariantHasFullCounterAdvance() throws {
        let result = ReassignmentResult(
            status: .ok,
            groups: [],
            counterAdvance: CounterAdvanceResult(
                task: CounterAdvanceEntry(advancedTo: 128, warning: nil),
                milestone: CounterAdvanceEntry(advancedTo: 42, warning: nil)
            )
        )
        let json = try encodeToJSONObject(result)
        #expect(json["status"] as? String == "ok")
        #expect((json["groups"] as? [Any])?.isEmpty == true)
        let advance = try #require(json["counterAdvance"] as? [String: Any])
        let task = try #require(advance["task"] as? [String: Any])
        #expect(task["advancedTo"] as? Int == 128)
        // warning key present (NSNull when nil)
        #expect(task.keys.contains("warning"))
        let milestone = try #require(advance["milestone"] as? [String: Any])
        #expect(milestone["advancedTo"] as? Int == 42)
    }

    @Test func reassignmentResultBusyVariantHasNullCounterAdvance() throws {
        let result = ReassignmentResult.busy
        let json = try encodeToJSONObject(result)
        #expect(json["status"] as? String == "busy")
        #expect((json["groups"] as? [Any])?.isEmpty == true)
        // counterAdvance key is always present, value is null in busy variant
        #expect(json.keys.contains("counterAdvance"))
        #expect(json["counterAdvance"] is NSNull)
    }

    @Test func reassignmentResultGroupShape() throws {
        let winnerId = UUID()
        let loserId = UUID()
        let entry = ReassignmentEntry(
            id: loserId, name: "Loser",
            previousDisplayId: 5, newDisplayId: 127,
            commentWarning: nil
        )
        let group = GroupResult(
            type: .task, displayId: 5,
            winner: GroupResultWinner(id: winnerId, name: "Winner"),
            reassignments: [entry], failure: nil
        )
        let result = ReassignmentResult(
            status: .ok, groups: [group],
            counterAdvance: CounterAdvanceResult(
                task: CounterAdvanceEntry(advancedTo: 128, warning: nil),
                milestone: nil
            )
        )
        let json = try encodeToJSONObject(result)
        let groupsArr = try #require(json["groups"] as? [[String: Any]])
        let groupDict = try #require(groupsArr.first)
        #expect(groupDict["type"] as? String == "task")
        #expect(groupDict["displayId"] as? Int == 5)
        let winner = try #require(groupDict["winner"] as? [String: Any])
        #expect(winner["id"] as? String == winnerId.uuidString)
        #expect(winner["name"] as? String == "Winner")
        let reassignments = try #require(groupDict["reassignments"] as? [[String: Any]])
        let reEntry = try #require(reassignments.first)
        #expect(reEntry["id"] as? String == loserId.uuidString)
        #expect(reEntry["previousDisplayId"] as? Int == 5)
        #expect(reEntry["newDisplayId"] as? Int == 127)
        #expect(reEntry.keys.contains("commentWarning"))
        #expect(groupDict.keys.contains("failure"))
    }

    @Test func reassignmentResultFailureCodeEncodesAsRawValue() throws {
        let group = GroupResult(
            type: .milestone, displayId: 9,
            winner: GroupResultWinner(id: UUID(), name: "W"),
            reassignments: [],
            failure: GroupFailure(code: .allocationFailed, message: "offline")
        )
        let result = ReassignmentResult(
            status: .ok, groups: [group],
            counterAdvance: CounterAdvanceResult(task: nil, milestone: nil)
        )
        let json = try encodeToJSONObject(result)
        let groupsArr = try #require(json["groups"] as? [[String: Any]])
        let failure = try #require(groupsArr.first?["failure"] as? [String: Any])
        #expect(failure["code"] as? String == "allocation-failed")
        #expect(failure["message"] as? String == "offline")
    }

    @Test func counterAdvanceWarningEncodesAsString() throws {
        let advance = CounterAdvanceResult(
            task: CounterAdvanceEntry(advancedTo: nil, warning: "retries exhausted"),
            milestone: nil
        )
        let result = ReassignmentResult(
            status: .ok, groups: [],
            counterAdvance: advance
        )
        let json = try encodeToJSONObject(result)
        let counterAdvance = try #require(json["counterAdvance"] as? [String: Any])
        let task = try #require(counterAdvance["task"] as? [String: Any])
        #expect(task["warning"] as? String == "retries exhausted")
        // advancedTo present but null
        #expect(task.keys.contains("advancedTo"))
        #expect(task["advancedTo"] is NSNull)
    }

    // MARK: - Helpers

    private func encodeToJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(value)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return try #require(obj as? [String: Any])
    }
}
