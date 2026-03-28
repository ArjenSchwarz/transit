import Foundation
import SwiftData

/// Singleton record whose sole purpose is to trigger CloudKit sync cycles.
///
/// A local SwiftData write reliably causes `NSPersistentCloudKitContainer` to
/// run a full export + import cycle. By updating `lastBeat` periodically, we
/// force CloudKit to pull remote changes — keeping the MCP server's query
/// results fresh even when macOS throttles push delivery.
@Model
final class SyncHeartbeat {
    static let singletonID = "sync-heartbeat"

    var id: String = "sync-heartbeat"
    var lastBeat: Date = Date()

    init() {}
}
