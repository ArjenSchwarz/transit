import Foundation
import CryptoKit

enum MCPRecordRevision {
    static func token(entity: String, fields: [String: Any]) throws -> String {
        let canonical = try MCPCanonicalJSON.encode(["version": 1, "entity": entity, "fields": fields])
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "r1:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func exactDate(_ date: Date?) throws -> Any {
        guard let date else { return NSNull() }
        let interval = date.timeIntervalSinceReferenceDate
        guard interval.isFinite else { throw MCPCanonicalJSON.Error.invalidValue }
        return String(interval.bitPattern, radix: 16)
    }

    static func uuid(_ value: UUID?) -> Any {
        value?.uuidString.lowercased() as Any? ?? NSNull()
    }
}
