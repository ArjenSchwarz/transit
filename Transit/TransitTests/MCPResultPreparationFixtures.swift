#if os(macOS)
import Foundation

/// Synthetic immutable values only: no model, store, clock or capture dependency.
@MainActor
enum MCPResultPreparationFixtures {
    static func pages(recordCount: Int = 2_000, pageSize: Int = 500, padding: Int = 512) throws -> [String] {
        var generator = Generator(seed: 0x2383_2012_05BD_000A)
        var pages: [String] = []
        for start in stride(from: 0, to: recordCount, by: pageSize) {
            var records: [String] = []
            for index in start..<min(start + pageSize, recordCount) {
                let uuid = String(format: "AA000000-0000-0000-0000-%012llX", UInt64(index + 1))
                let name = "T-\(index) 🛰 \"saved\"\n" + String(generator.next(), radix: 16)
                let detail = String(repeating: "x", count: padding) + "\n é / é ~ \\"
                let number = index.isMultiple(of: 2) ? "1E-9999" : "999999999999999999999999999999999999999"
                records.append("{\"taskId\":\(try quoted(uuid)),\"displayId\":\(index),"
                    + "\"name\":\(try quoted(name)),\"description\":\(try quoted(detail)),"
                    + "\"revision\":\(try quoted("r1:" + String(repeating: "a", count: 64))),"
                    + "\"future\":{\"number\":\(number),\"flag\":false,\"nullable\":null}}")
            }
            pages.append("[" + records.joined(separator: ",\n") + "]")
        }
        return pages
    }

    static let metadataText = #"""
        {"me.nore.ig.transit/read":{"asOf":"2026-10-03T09:00:00.000Z",
        "snapshotId":"frozen-original-capture","freshness":{"assessment":"unknown"},
        "read":{"policy":"cached","budgetMs":5000},"future":{"value":1E-9999,"flag":false,"nullable":null}}}
        """#

    private static func quoted(_ text: String) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed])
        guard let encoded = String(bytes: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return encoded
    }

    private struct Generator {
        var seed: UInt64
        mutating func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed
        }
    }
}
#endif
