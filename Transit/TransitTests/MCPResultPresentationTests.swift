#if os(macOS)
import Foundation
import Synchronization
import Testing
@testable import Transit

@MainActor struct MCPResultPresentationTests {
    @Test func protectedTaskRecordAndRelationshipHaveDistinctUnavailablePointers() throws {
        let text = "{\"record\":{\"taskId\":\"\(Self.taskID)\",\"displayId\":7," +
            "\"projectId\":\"\(Self.projectID)\",\"comments\":[{\"id\":\"\(Self.otherID)\"}]} }"
        let source = try Self.source(text)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("update_task"))
        #expect(Self.links(presentation) == ["/record|task|\(Self.taskID)",
                                           "/record/projectId|project|\(Self.projectID)"])
        #expect(presentation.evidence == .established)
        #expect(presentation.errorCategory == nil)
        #expect(presentation.links.allSatisfy {
            $0.availability == "unavailable" && $0.reason == "navigation_not_supported"
        })
        #expect(source.originalText == text)
    }

    @Test func queryArrayOrderAndUUIDsSurviveDuplicateDisplayIDs() throws {
        let records = (0..<12).map { index in
            "{\"taskId\":\"\(Self.numberedID(index))\",\"displayId\":9}"
        }
        let source = try Self.source("{\"results\":[" + records.joined(separator: ",") + "]}")
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
        #expect(Self.links(presentation) == (0..<12).map { "/results/\($0)|task|\(Self.numberedID($0))" })
    }

    @Test func selectorSuccessUsesNestedTaskAndSavedProjectWithoutLinkingRequestedFailures() throws {
        let text = "{\"results\":[{\"index\":0,\"requested\":{\"displayId\":9},\"task\":{" +
            "\"taskId\":\"\(Self.taskID)\",\"displayId\":9,\"projectId\":\"\(Self.projectID)\"}}," +
            "{\"index\":1,\"requested\":{\"taskId\":\"\(Self.otherID)\"}," +
            "\"error\":{\"code\":\"TASK_NOT_FOUND\",\"message\":\"Absent selector\"}}],\"nextCursor\":null}"
        let source = try Self.source(text)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
        #expect(Self.links(presentation) == ["/results/0/task|task|\(Self.taskID)",
                                           "/results/0/task/projectId|project|\(Self.projectID)"])
        #expect(presentation.evidence == .established)
        #expect(presentation.errorCategory == nil)
        #expect(source.originalText == text)
    }

    @Test func historicalRootTaskArrayPreservesSavedProjectReferencesAndArrayOrder() throws {
        let text = "[{\"taskId\":\"\(Self.taskID)\",\"displayId\":9,\"projectId\":\"\(Self.projectID)\"}," +
            "{\"taskId\":\"\(Self.otherID)\",\"displayId\":9,\"projectId\":\"\(Self.projectID)\"}]"
        let source = try Self.source(text, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
        #expect(Self.links(presentation) == ["/0|task|\(Self.taskID)", "/0/projectId|project|\(Self.projectID)",
                                           "/1|task|\(Self.otherID)", "/1/projectId|project|\(Self.projectID)"])
        #expect(source.document?.originalUTF8 == Data(text.utf8))
    }

    @Test func projectsArrayUsesProjectIdentityAndDoesNotSearchUnknownNestedIDs() throws {
        let text = "[{\"projectId\":\"\(Self.projectID)\"," +
            "\"extra\":{\"taskId\":\"\(Self.taskID)\"}}]"
        let source = try Self.source(text)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("get_projects"))
        #expect(Self.links(presentation) == ["/0|project|\(Self.projectID)"])
    }

    @Test(arguments: ["record", "currentRecord", "recordBeforeDeletion"])
    func documentedTaskEvidencePositionsUseTheirOwnPointer(field: String) throws {
        let source = try Self.source("{\"\(field)\":{\"taskId\":\"\(Self.taskID)\"}}")
        let presentation = try MCPResultAdapter.present(source, context: Self.context("update_task"))
        #expect(Self.links(presentation) == ["/\(field)|task|\(Self.taskID)"])
    }

    @Test func missingMalformedAndUndeclaredIdentitiesNeverInventLinks() throws {
        let text = "{\"results\":[{}, {\"taskId\":null}, {\"taskId\":9}, {\"taskId\":\"not-a-uuid\"}]," +
            "\"unknown\":{\"taskId\":\"\(Self.taskID)\"}}"
        let source = try Self.source(text)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
        #expect(presentation.links.isEmpty)
        let milestone = try Self.source("{\"record\":{\"id\":\"\(Self.otherID)\"}}")
        #expect(try MCPResultAdapter.present(milestone, context: Self.context("create_milestone")).links.isEmpty)
        let wrongTaskField = try Self.source("{\"record\":{\"id\":\"\(Self.taskID)\"}}")
        #expect(try MCPResultAdapter.present(wrongTaskField, context: Self.context("update_task")).links.isEmpty)
    }

    @Test func milestoneQueryLinksOnlySavedProjectReferencesInRootArrayOrder() throws {
        let text = "[{\"milestoneId\":\"\(Self.taskID)\",\"projectId\":\"\(Self.projectID)\"}," +
            "{\"milestoneId\":\"\(Self.projectID)\",\"projectId\":\"\(Self.otherID)\"}," +
            "{\"milestoneId\":\"\(Self.otherID)\",\"projectId\":null}," +
            "{\"milestoneId\":\"\(Self.taskID)\",\"projectId\":\"not-a-uuid\"}]"
        let source = try Self.source(text, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_milestones"))
        #expect(Self.links(presentation) == ["/0/projectId|project|\(Self.projectID)",
                                           "/1/projectId|project|\(Self.otherID)"])
        #expect(presentation.links.allSatisfy { $0.entityType == .project })
        #expect(presentation.errorCategory == nil)
        #expect(source.originalText == text)
    }

    @Test func providerPositionsAreValidatedAgainstSameSourceAndSortedDeterministically() throws {
        let source = try Self.source("{\"z\":\"\(Self.projectID)\",\"a\":{\"taskId\":\"\(Self.taskID)\"}}")
        let positions: [MCPResultEntityPosition] = [
            .init(entityType: .project, sourcePath: "/z"),
            .init(entityType: .task, sourcePath: "/a"),
            .init(entityType: .task, sourcePath: "/missing")
        ]
        let context = Self.context("future_provider", positions: positions)
        let presentation = try MCPResultAdapter.present(source, context: context)
        #expect(Self.links(presentation) == ["/a|task|\(Self.taskID)", "/z|project|\(Self.projectID)"])
        #expect(Self.signature(presentation) == Self.signature(try MCPResultAdapter.present(source, context: context)))
    }

    @Test func pointersUnescapeTokensAndCompareDecodedUnicodeScalarsExactly() throws {
        let source = try Self.source("{\"é\":\"\(Self.taskID)\",\"e\\u0301\":\"\(Self.projectID)\"," +
                                    "\"a/b~c\":\"\(Self.otherID)\"}")
        let positions: [MCPResultEntityPosition] = [
            .init(entityType: .task, sourcePath: "/é"),
            .init(entityType: .project, sourcePath: "/e\u{301}"),
            .init(entityType: .task, sourcePath: "/a~1b~0c")
        ]
        let presentation = try MCPResultAdapter.present(source, context: Self.context("future", positions: positions))
        #expect(presentation.links.count == 3)
        #expect(presentation.links.first { Array($0.sourcePath.unicodeScalars) == Array("/é".unicodeScalars) }?
            .entityId.uuidString == Self.taskID)
        #expect(presentation.links.first { Array($0.sourcePath.unicodeScalars) == Array("/e\u{301}".unicodeScalars) }?
            .entityId.uuidString == Self.projectID)
        #expect(presentation.links.first { $0.sourcePath == "/a~1b~0c" }?.entityId.uuidString == Self.otherID)
    }

    @Test func seededUnknownFieldsAndCollisionsPreserveEvidenceAndDeterministicLinkSelection() throws {
        for seed in UInt64(0)..<64 {
            var generator = MCPJSONFixtureGenerator(seed: seed)
            let unknown = generator.value()
            if try Self.collisionInvariant(unknown) { continue }
            let minimal = MCPJSONFixtureValue.minimizedFailure(unknown) {
                (try? Self.collisionInvariant($0)) != true
            }
            Issue.record("Presentation invariant failed seed=\(seed); unknown=\(try minimal.json())")
            return
        }
    }

    @Test(arguments: [MCPResultErrorCategory.invalidInput, .notFound, .ambiguousIdentity, .revisionConflict,
                      .keyConflict, .storageFailure, .incoherentCapture, .admissionBusy, .deadlineExceeded,
                      .retentionCapacity, .invalidCursor, .expiredCursor, .serializationFailure,
                      .outcomeUncertain, .unclassifiedHistorical, .internalFailure])
    func explicitProviderFailurePhaseHasFiniteCategory(category: MCPResultErrorCategory) throws {
        let source = try MCPResultAdapter.source(text: "Message deliberately gives no category", isError: true,
                                               origin: .plainText, evidence: .established)
        let context = Self.context("query_tasks", failure: .init(category: category, diagnostic: "phase"))
        let presentation = try MCPResultAdapter.present(source, context: context)
        #expect(presentation.errorCategory == category)
    }

    @Test func invalidSnapshotRestartsReadWithoutChangingSavedFailure() throws {
        let text = #"{"error":{"code":"INVALID_SNAPSHOT","message":"Start a new summary"}}"#
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_project_summaries"))
        #expect(presentation.errorCategory == .invalidCursor)
        #expect(presentation.recovery?.direction == .restartRead)
        #expect(source.originalText == text)
    }

    @Test(arguments: MCPPresentationCodeFixture.all)
    func knownHistoricCodesMapWithoutChangingOriginalFields(fixture: MCPPresentationCodeFixture) throws {
        let text = "{\"error\":{\"code\":\"\(fixture.code)\",\"message\":\"saved message\"},\"extra\":null}"
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
        #expect(presentation.errorCategory == fixture.category)
        #expect(source.originalText == text)
        #expect(source.originalIsError == true)
        #expect(source.document?.originalUTF8 == Data(text.utf8))
    }
}

@MainActor extension MCPResultPresentationTests {
    @Test func acceptedUncertainWriteCannotAcquireNoEffectRetryFromItsErrorCode() throws {
        let text = #"{"outcome":"uncertain","accepted":true,"retryAction":"reconcile","# +
            #""error":{"code":"INVALID_INPUT"}}"#
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.errorCategory == .outcomeUncertain)
        #expect(presentation.recovery?.direction == .reconcileOriginalWrite)
        guard case .protectedWrite(let key) = presentation.recovery?.mutation else {
            Issue.record("Lost original protected recovery key")
            return
        }
        #expect(key == Self.key)
        #expect(source.originalText == text)
    }

    @Test func contradictorySavedRetryEvidenceBecomesUnestablishedWithoutRewritingIt() throws {
        let text = #"{"outcome":"committed","accepted":true,"retryAction":"new_request_new_key","# +
            #""error":{"code":"INVALID_INPUT"}}"#
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.evidence == .unestablished)
        #expect(presentation.errorCategory == .outcomeUncertain)
        #expect(presentation.recovery?.direction == .reconcileOriginalWrite)
        #expect(source.originalText == text)
    }

    @Test func unsupportedUnestablishedAndUnreadableWritesRequireOriginalEvidenceReconciliation() throws {
        for text in ["{broken", #"{"contractVersion":999,"outcome":"future","accepted":null}"#] {
            let source = try MCPResultAdapter.source(text: text, isError: false, origin: .retainedJSON,
                                                   evidence: .unestablished)
            let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
            #expect(presentation.evidence == .unestablished)
            #expect(presentation.errorCategory == .outcomeUncertain)
            #expect(presentation.recovery?.direction == .reconcileOriginalWrite)
            #expect(source.originalText == text)
            #expect(source.originalIsError == false)
        }
    }

    @Test func unknownHistoricCodeIsExplicitAndDoesNotPromiseReadRetrySafety() throws {
        let source = try Self.source(#"{"error":{"code":"FUTURE_UNKNOWN","message":"READ_TIMEOUT"}}"#,
                                     isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
        #expect(presentation.errorCategory == .unclassifiedHistorical)
        #expect(presentation.recovery?.direction != .retryIdenticalRead)
    }

    @Test func protectedRejectedSourceRetryDirectionRemainsAuthoritative() throws {
        let text = #"{"outcome":"rejected","accepted":false,"retryAction":"new_request_new_key","# +
            #""error":{"code":"REVISION_CONFLICT"}}"#
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.errorCategory == .revisionConflict)
        #expect(presentation.recovery?.direction == .followSource)
        #expect(source.originalText == text)
    }

    @Test(arguments: MCPPresentationRejectionFixture.all)
    func establishedV1InternalRejectionsFollowOriginalRetryEvidence(
        fixture: MCPPresentationRejectionFixture
    ) throws {
        let text = Self.v1WriteEvidence(code: fixture.code, accepted: fixture.accepted)
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.evidence == .established)
        #expect(presentation.errorCategory == .internalFailure)
        #expect(presentation.recovery?.direction == .followSource)
        guard case .protectedWrite(let key) = presentation.recovery?.mutation else {
            Issue.record("Lost original key from known rejected outcome")
            return
        }
        #expect(key == Self.key)
        #expect(source.originalText == text)
        #expect(source.originalIsError == true)
        #expect(source.document?.originalUTF8 == Data(text.utf8))
    }

    @Test func unknownV1RejectedCodeDoesNotAcquireSafeRetryFromKnownOutcome() throws {
        let text = Self.v1WriteEvidence(code: "FUTURE_UNKNOWN", accepted: true)
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.errorCategory == .unclassifiedHistorical)
        #expect(presentation.recovery?.direction == .reconcileOriginalWrite)
        #expect(source.originalText == text)
    }

    @Test func uncertainV1InternalFailureOverridesNewKeyLookingCategory() throws {
        let text = Self.v1WriteEvidence(code: "INTERNAL_ERROR", accepted: true,
                                        outcome: "uncertain", retry: "reconcile")
        let source = try Self.source(text, isError: true, origin: .retainedJSON)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.errorCategory == .outcomeUncertain)
        #expect(presentation.recovery?.direction == .reconcileOriginalWrite)
        #expect(source.originalText == text)
    }

    @Test func unestablishedV1KnownRejectionCannotGainFollowSourceRetry() throws {
        let text = Self.v1WriteEvidence(code: "INTERRUPTED_BEFORE_COMMIT", accepted: true)
        let source = try MCPResultAdapter.source(text: text, isError: true, origin: .retainedJSON,
                                               evidence: .unestablished)
        let presentation = try MCPResultAdapter.present(source, context: Self.protectedContext())
        #expect(presentation.evidence == .unestablished)
        #expect(presentation.errorCategory == .outcomeUncertain)
        #expect(presentation.recovery?.direction == .reconcileOriginalWrite)
        #expect(source.originalText == text)
    }

    @Test func readAndMaintenanceRecoveryDirectionsStaySeparate() throws {
        let source = try Self.source(#"{"error":{"code":"READ_TIMEOUT"}}"#, isError: true)
        #expect(try MCPResultAdapter.present(source, context: Self.context("query_tasks"))
            .recovery?.direction == .retryIdenticalRead)
        let expired = try Self.source(#"{"error":{"code":"QUERY_EXPIRED"}}"#, isError: true)
        #expect(try MCPResultAdapter.present(expired, context: Self.context("query_tasks"))
            .recovery?.direction == .restartRead)
        let maintenance = Self.context("reassign_duplicate_display_ids",
                                       failure: .init(category: .outcomeUncertain, diagnostic: "may have effects"),
                                       mutation: .unprotectedMaintenance(tool: "reassign_duplicate_display_ids"))
        let presentation = try MCPResultAdapter.present(source, context: maintenance)
        #expect(presentation.recovery?.direction == .reconcileMaintenance)
        guard case .unprotectedMaintenance(let tool) = presentation.recovery?.mutation else {
            Issue.record("Maintenance acquired an invented protected key")
            return
        }
        #expect(tool == "reassign_duplicate_display_ids")
    }

    @Test func presentationPropagatesOriginalCheckpointAndBoundaryTypedFailure() throws {
        let source = try Self.source("{}")
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPResultAdapter.present(source, context: Self.context("query_tasks")) {
                throw MCPJSONCheckpointFailure.cancelled
            }
        }
        #expect(throws: MCPResultBoundaryError.resourceLimit) {
            try MCPResultAdapter.present(source, context: Self.context("query_tasks")) {
                throw MCPResultBoundaryError.resourceLimit
            }
        }
    }

    @Test func largePresentationTraversalChecksWorkerRepeatedly() throws {
        let records = (0..<2_000).map { "{\"taskId\":\"\(Self.numberedID($0))\"}" }
        let source = try Self.source("{\"results\":[" + records.joined(separator: ",") + "]}")
        let count = Mutex(0)
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPResultAdapter.present(source, context: Self.context("query_tasks")) {
                if count.withLock({ $0 += 1; return $0 }) == 2 { throw MCPJSONCheckpointFailure.cancelled }
            }
        }
        #expect(count.withLock { $0 } == 2)
    }
}

@MainActor private extension MCPResultPresentationTests {
    static var taskID: String { "11111111-1111-1111-1111-111111111111" }
    static var projectID: String { "22222222-2222-2222-2222-222222222222" }
    static var otherID: String { "33333333-3333-3333-3333-333333333333" }
    static var key: MCPProtectedRecoveryKey { .init(tool: "update_task", idempotencyKey: "original-key") }

    static func numberedID(_ index: Int) -> String {
        "00000000-0000-0000-0000-" + String(format: "%012d", index)
    }

    static func source(_ text: String, isError: Bool? = nil,
                       origin: MCPResultOrigin = .generatedJSON) throws -> MCPResultSource {
        try MCPResultAdapter.source(text: text, isError: isError, origin: origin, evidence: .established)
    }

    static func context(_ tool: String, failure: MCPResultFailure? = nil,
                        mutation: MCPMutationRecoveryContext? = nil,
                        positions: [MCPResultEntityPosition] = []) -> MCPResultContext {
        .init(tool: tool, semanticFailure: failure, mutationRecovery: mutation, entityPositions: positions)
    }

    static func protectedContext() -> MCPResultContext {
        context("update_task", mutation: .protectedWrite(key))
    }

    static func v1WriteEvidence(code: String, accepted: Bool, outcome: String = "rejected",
                                retry: String = "new_request_new_key") -> String {
        // accepted=true records key binding; a validated terminal rejection still establishes no commit.
        let terminal = accepted && outcome == "rejected" ?
            #","completedAt":"2026-10-03T00:00:00Z","replayExpiresAt":"2026-10-10T00:00:00Z""# : ""
        return #"{"contractVersion":1,"tool":"update_task","idempotencyKey":"original-key","# +
            "\"outcome\":\"\(outcome)\",\"accepted\":\(accepted),\"retryAction\":\"\(retry)\"," +
            "\"error\":{\"code\":\"\(code)\",\"message\":\"Saved failure\"},\"unknown\":null" + terminal + "}"
    }

    static func links(_ presentation: MCPResultPresentation) -> [String] {
        presentation.links.map { "\($0.sourcePath)|\($0.entityType.rawValue)|\($0.entityId.uuidString)" }
    }

    static func signature(_ presentation: MCPResultPresentation) -> [String] {
        [presentation.evidence.rawValue, presentation.errorCategory?.rawValue ?? "absent",
         presentation.recovery?.direction.rawValue ?? "absent"] + links(presentation)
    }

    static func collisionInvariant(_ unknown: MCPJSONFixtureValue) throws -> Bool {
        let text = "{\"record\":{\"taskId\":\"\(taskID)\"},\"source\":" + (try unknown.json()) +
            ",\"presentation\":null,\"links\":[],\"errorCategory\":\"collision\"}"
        let source = try Self.source(text)
        let context = Self.context("update_task")
        let before = source.document?.originalUTF8
        let first = try MCPResultAdapter.present(source, context: context)
        let second = try MCPResultAdapter.present(source, context: context)
        return signature(first) == signature(second) && links(first) == ["/record|task|\(taskID)"] &&
            first.evidence == .established && first.errorCategory == nil && source.originalText == text &&
            source.document?.originalUTF8 == before
    }
}

#endif
