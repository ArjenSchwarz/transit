import Foundation
import Testing
@testable import Transit

@MainActor struct MCPCanonicalJSONTests {
    @Test func generatedObjectPermutationsRoundTrip() throws {
        for seed in 0..<100 {
            let entries: [(String, Any)] = [
                ("z", [seed, true, NSNull()] as [Any]),
                ("a", ["nested": ["value": "\(seed)", "null": NSNull()] as [String: Any]]),
                ("quoted\"", "backslash\\\n\u{0000}")
            ]
            let forward = Dictionary(uniqueKeysWithValues: entries)
            let reverse = Dictionary(uniqueKeysWithValues: entries.reversed())
            let encoded = try MCPCanonicalJSON.encode(forward)
            #expect(encoded == (try MCPCanonicalJSON.encode(reverse)))
            let decoded = try JSONSerialization.jsonObject(with: Data(encoded.utf8))
            #expect(encoded == (try MCPCanonicalJSON.encode(decoded)))
        }
    }

    @Test func finiteNumbersRetainLosslessIdentity() throws {
        let adjacent = [1.0, 1.0000000000000002, 1.0000000000000004]
        let encodings = try adjacent.map { try MCPCanonicalJSON.encode($0) }
        #expect(Set(encodings).count == adjacent.count)
        for value in [1e300, 1e-300, Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude] {
            let encoded = try MCPCanonicalJSON.encode(value)
            let decoded = try JSONSerialization.jsonObject(with: Data(encoded.utf8), options: [.fragmentsAllowed])
            #expect((decoded as? NSNumber)?.doubleValue == value)
            #expect(try MCPCanonicalJSON.encode(decoded) == encoded)
        }
        for value in [1.0, 10.0, 1000.0, -10.0] {
            #expect(try MCPCanonicalJSON.encode(value) == MCPCanonicalJSON.encode(Int(value)))
        }
    }

    @Test func typedValuesAndPresenceRemainDistinct() throws {
        #expect(try MCPCanonicalJSON.encode(["v": true]) != MCPCanonicalJSON.encode(["v": 1]))
        #expect(try MCPCanonicalJSON.encode(["v": NSNull()]) != MCPCanonicalJSON.encode([String: Any]()))
        #expect(try MCPCanonicalJSON.encode(["v": 1]) == MCPCanonicalJSON.encode(["v": 1.0]))
        #expect(try MCPCanonicalJSON.encode(["v": -0.0]) == MCPCanonicalJSON.encode(["v": 0]))
        #expect(try MCPCanonicalJSON.encode([1, 2]) != MCPCanonicalJSON.encode([2, 1]))
        #expect(throws: (any Error).self) { try MCPCanonicalJSON.encode(Double.infinity) }
    }
}
