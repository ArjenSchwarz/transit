import Foundation
import SwiftData

/// Completed outcomes share the domain store's commit boundary. Scope remains
/// local even when CloudKit imports receipts created by another device.
@Model
nonisolated final class MCPWriteReceipt {
    var id: UUID = UUID()
    var localScopeID: String = ""
    var tool: String = ""
    var key: String = ""
    var formatVersion: Int = 1
    var requestJSON: String = ""
    var stateRawValue: String = "accepted"
    var acceptedAt: Date = Date()
    var completedAt: Date?
    var expiresAt: Date?
    var resultJSON: String?
    var resultIsError: Bool?

    init(id: UUID = UUID(), localScopeID: String, tool: String, key: String,
         formatVersion: Int = 1, requestJSON: String, acceptedAt: Date) {
        self.id = id
        self.localScopeID = localScopeID
        self.tool = tool
        self.key = key
        self.formatVersion = formatVersion
        self.requestJSON = requestJSON
        self.acceptedAt = acceptedAt
    }
}
