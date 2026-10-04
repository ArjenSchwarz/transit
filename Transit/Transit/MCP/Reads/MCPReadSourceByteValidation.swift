#if os(macOS)
import Foundation

nonisolated enum MCPReadSourceByteValidation {
    /// Traverse without an unchecked count scan or temporary byte array. The supplied checkpoint
    /// belongs to the original operation and runs at most 256 byte comparisons apart.
    static func matches(_ original: String, _ prepared: String,
                        checkpoint: @Sendable () throws -> Void) throws -> Bool {
        try checkpoint()
        var left = original.utf8.makeIterator()
        var right = prepared.utf8.makeIterator()
        var compared = 0
        while true {
            if compared == 256 { try checkpoint(); compared = 0 }
            let lhs = left.next()
            let rhs = right.next()
            guard lhs == rhs else { try checkpoint(); return false }
            guard lhs != nil else { try checkpoint(); return true }
            compared += 1
        }
    }
}
#endif
