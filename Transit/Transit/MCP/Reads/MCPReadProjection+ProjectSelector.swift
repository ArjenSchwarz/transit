#if os(macOS)
import Foundation

extension MCPReadProjection {
    static func projectSelector(_ args: [String: Any],
                                validateIgnoredName: Bool = true) throws -> (UUID?, String?) {
        let id: UUID?
        if let raw = args["projectId"] {
            guard let text = raw as? String, let parsed = UUID(uuidString: text) else {
                throw MCPTaskQueryError.invalid("Invalid projectId: expected a UUID string")
            }
            id = parsed
        } else { id = nil }
        if id == nil || validateIgnoredName, args["project"] != nil, !(args["project"] is String) {
            throw MCPTaskQueryError.invalid("project must be a string")
        }
        let name = (args["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (id, name)
    }
}
#endif
