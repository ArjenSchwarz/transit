#if os(macOS)
import Foundation
import Synchronization
import Testing
@testable import Transit

@MainActor struct MCPJSONDocumentTests {
    @Test func completeValuesPreserveWhitespaceAndNumberLexemes() throws {
        let text = " \n{\"huge\":18446744073709551616,\"fraction\":1.00000000000000000001," +
            "\"exp\":-2.300e+400,\"negativeZero\":-0,\"bool\":true,\"null\":null}\t "
        let document = try MCPJSONDocument.parse(text)
        #expect(document.originalUTF8 == Data(text.utf8))
        let expected = MCPJSONFixtureValue.object([
            .init(name: "huge", value: .number("18446744073709551616")),
            .init(name: "fraction", value: .number("1.00000000000000000001")),
            .init(name: "exp", value: .number("-2.300e+400")),
            .init(name: "negativeZero", value: .number("-0")),
            .init(name: "bool", value: .boolean(true)),
            .init(name: "null", value: .null)
        ])
        #expect(expected.matches(document.value))
    }

    @Test func escapedStringsDecodeWithoutChangingOriginalBytes() throws {
        let text = #"{"\u0061":"\uD83D\uDE80\n\t\"\\\/","東京":"e\u0301"}"#
        let document = try MCPJSONDocument.parse(Data(text.utf8))
        #expect(document.originalUTF8 == Data(text.utf8))
        let expected = MCPJSONFixtureValue.object([
            .init(name: "a", value: .string("🚀\n\t\"\\/")),
            .init(name: "東京", value: .string("e\u{0301}"))
        ])
        #expect(expected.matches(document.value))
    }

    @Test func canonicallyEquivalentButScalarDistinctObjectKeysRemainDistinct() throws {
        let text = #"{"\u00e9":1,"e\u0301":2}"#
        let document = try MCPJSONDocument.parse(text)
        #expect(document.originalUTF8 == Data(text.utf8))
        guard case .object(let members) = document.value else {
            Issue.record("Expected two distinct JSON object keys")
            return
        }
        #expect(members.count == 2)
        #expect(members.map { $0.name.unicodeScalars.map(\.value) } == [[0xE9], [0x65, 0x301]])
        let expected = MCPJSONFixtureValue.object([
            .init(name: "\u{E9}", value: .number("1")),
            .init(name: "e\u{301}", value: .number("2"))
        ])
        #expect(expected.matches(document.value))
    }

    @Test func seededCompleteValuesRetainTypedTreeAndExactFragment() throws {
        for seed in UInt64(0)..<128 {
            var generator = MCPJSONFixtureGenerator(seed: seed)
            let expected = generator.value()
            let text = " \n" + (try expected.json()) + "\t"
            do {
                let document = try MCPJSONDocument.parse(text)
                if expected.matches(document.value), document.originalUTF8 == Data(text.utf8) { continue }
            } catch {
                // A valid-value parse error is a property failure, not invalid-input success.
            }
            let minimal = MCPJSONFixtureValue.minimizedFailure(expected) { candidate in
                guard let text = try? candidate.json(), let parsed = try? MCPJSONDocument.parse(text) else {
                    return true
                }
                return !candidate.matches(parsed.value) || parsed.originalUTF8 != Data(text.utf8)
            }
            let counterexample = try minimal.json()
            Issue.record("Valid JSON property failed; seed=\(seed), minimal=\(counterexample)")
            return
        }
    }

    @Test(arguments: [
        "", " ", "{}[]", "true false", "{\"a\":1,\"a\":2}", #"{"a":1,"\u0061":2}"#,
        #"{"é":1,"\u00e9":2}"#,
        "[1,]", "{\"a\":}", "{\"a\":1,}", "01", "-", "+1", "1.", "1e", "1e+", "NaN",
        #""\x20""#, #""\uD800""#, #""\uDC00""#, #""\uD800\u0041""#, "\"line\nfeed\""
    ])
    func rejectsAmbiguousOrMalformedJSON(text: String) {
        #expect(throws: MCPResultBoundaryError.invalidJSON) { try MCPJSONDocument.parse(text) }
    }

    @Test func rejectsInvalidUTF8RatherThanReplacingBytes() {
        for bytes: [UInt8] in [[0x22, 0xC3, 0x28, 0x22], [0x22, 0xED, 0xA0, 0x80, 0x22], [0xFF]] {
            #expect(throws: MCPResultBoundaryError.invalidJSON) { try MCPJSONDocument.parse(Data(bytes)) }
        }
    }

    @Test func injectedWorkerCheckpointFailurePropagates() {
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPJSONDocument.parse("[0,1,2]") { throw MCPJSONCheckpointFailure.cancelled }
        }
    }

    @Test(arguments: [31, 32])
    func admittedContainerDepthPreservesCompleteValue(depth: Int) throws {
        let text = Self.nestedContainers(depth: depth)
        let document = try MCPJSONDocument.parse(text)
        #expect(document.originalUTF8 == Data(text.utf8))
        var current = document.value
        for level in 0..<depth {
            if level.isMultiple(of: 2), case .array(let values) = current, values.count == 1 {
                current = values[0]
            } else if !level.isMultiple(of: 2), case .object(let members) = current,
                      members.count == 1, members[0].name == "value" {
                current = members[0].value
            } else {
                Issue.record("Container depth or shape changed at level \(level)")
                return
            }
        }
        #expect(current == .null)
    }

    @Test func depth33IsAResourceLimitRatherThanMalformedJSON() {
        #expect(throws: MCPResultBoundaryError.resourceLimit) {
            try MCPJSONDocument.parse(Self.nestedContainers(depth: 33))
        }
    }

    @Test func wide2000RecordArrayIsNotAContainerDepthFailure() throws {
        let records = (0..<2_000).map { "{\"index\":\($0),\"nullable\":null}" }
        let text = "[" + records.joined(separator: ",") + "]"
        let document = try MCPJSONDocument.parse(text)
        #expect(document.originalUTF8 == Data(text.utf8))
        guard case .array(let values) = document.value else {
            Issue.record("Expected wide record array")
            return
        }
        #expect(values.count == 2_000)
        for (index, value) in values.enumerated() {
            let expected = MCPJSONFixtureValue.object([
                .init(name: "index", value: .number(String(index))),
                .init(name: "nullable", value: .null)
            ])
            #expect(expected.matches(value))
        }
    }

    @Test func depthLimitDoesNotReplaceOriginalWorkerCheckpointFailure() {
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPJSONDocument.parse(Self.nestedContainers(depth: 33)) {
                throw MCPJSONCheckpointFailure.cancelled
            }
        }
    }

    @Test func largeStringParsingChecksOriginalWorkerRepeatedly() {
        let checks = Mutex(0)
        let text = "\"" + String(repeating: "東京🛰️", count: 8_000) + "\""
        #expect(throws: MCPJSONCheckpointFailure.cancelled) {
            try MCPJSONDocument.parse(text) {
                let count = checks.withLock { value in value += 1; return value }
                if count == 2 { throw MCPJSONCheckpointFailure.cancelled }
            }
        }
        #expect(checks.withLock { $0 } == 2)
    }

    @Test func shrinkerKeepsValidCandidatesAndFindsSmallCounterexample() throws {
        let original = MCPJSONFixtureValue.array([.string("long"), .number("18446744073709551616")])
        let minimal = MCPJSONFixtureValue.minimizedFailure(original) { _ in true }
        #expect(minimal == .array([]))
        #expect(try minimal.json() == "[]")
        #expect(original.shrinks().allSatisfy { (try? $0.json()) != nil })
    }

    private static func nestedContainers(depth: Int) -> String {
        var text = "null"
        for level in (0..<depth).reversed() {
            text = level.isMultiple(of: 2) ? "[" + text + "]" : "{\"value\":" + text + "}"
        }
        return " \n" + text + "\t"
    }
}

nonisolated enum MCPJSONCheckpointFailure: Error, Equatable {
    case cancelled
}
#endif
