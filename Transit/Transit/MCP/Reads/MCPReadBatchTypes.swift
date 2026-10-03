#if os(macOS)
import Foundation

nonisolated struct MCPReadBatchWork: Sendable {
    let timeout: Data
    let busy: Data
    let responds: Bool
    let worker: @Sendable (MCPReadOperation) async -> PreparedReadResult
}

nonisolated enum MCPReadBatchElement: Sendable {
    case fixed(Data?)
    case read(MCPReadBatchWork)
}

/// Completed captures wait here outside the terminal lock. One physical permit
/// remains held by the designated assembly worker until final assembly finishes.
actor MCPReadBatchCollector {
    private var values: [PreparedReadResult?]
    private var cancelled = false
    private var remaining: Int
    private var waiter: CheckedContinuation<[PreparedReadResult?], Never>?

    init(values: [PreparedReadResult?], remaining: Int) {
        self.values = values
        self.remaining = remaining
    }

    func complete(_ position: Int, value: PreparedReadResult?) -> [any MCPPreparedPublication] {
        if cancelled { return value?.publications ?? [] }
        values[position] = value
        remaining -= 1
        if remaining == 0 {
            waiter?.resume(returning: values)
            waiter = nil
        }
        return []
    }

    func cancel() -> [any MCPPreparedPublication] {
        cancelled = true
        let retired = values
        values = []
        waiter?.resume(returning: [])
        waiter = nil
        return retired.compactMap { $0 }.flatMap(\.publications)
    }

    func all() async -> [PreparedReadResult?] {
        if remaining == 0 { return values }
        return await withCheckedContinuation { waiter = $0 }
    }
}

nonisolated enum MCPReadBatchEncoding {
    static func array(_ values: [Data?]) -> Data? {
        let responses = values.compactMap { $0 }
        guard !responses.isEmpty else { return nil }
        var bytes = Data("[".utf8)
        for (position, response) in responses.enumerated() {
            if position != 0 { bytes.append(contentsOf: ",".utf8) }
            bytes.append(response)
        }
        bytes.append(contentsOf: "]".utf8)
        return bytes
    }
}
#endif
