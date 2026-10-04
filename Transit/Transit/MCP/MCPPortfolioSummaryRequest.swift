#if os(macOS)
import Foundation

nonisolated struct MCPPortfolioRequestError: Error, Sendable {
    let code: String
    let message: String

    static func invalid(_ message: String) -> Self { Self(code: "INVALID_INPUT", message: message) }
}

nonisolated enum MCPPortfolioSummaryRequest: Sendable {
    case initial(window: CompletionWindow, limit: Int, project: ReadProjectSelector?, policy: MCPReadPolicy)
    case replay(snapshotId: String)
    case continuation(cursor: String, policy: MCPReadPolicy?)

    @MainActor static func parse(_ arguments: [String: Any]) throws -> Self {
        if let raw = arguments["snapshotId"] {
            guard arguments.count == 1 else {
                throw MCPPortfolioRequestError.invalid("Summary replay requires snapshotId only")
            }
            guard let id = raw as? String, UUID(uuidString: id) != nil else {
                throw MCPPortfolioRequestError(
                    code: "INVALID_SNAPSHOT", message: "Invalid snapshot; start a new summary")
            }
            return .replay(snapshotId: id)
        }
        if let raw = arguments["cursor"] {
            guard Set(arguments.keys).isSubset(of: ["cursor", "readPolicy"]) else {
                throw MCPPortfolioRequestError.invalid("Continuation permits only cursor and readPolicy")
            }
            guard let policy = MCPReadRefreshPolicy.parse(arguments["readPolicy"]) else {
                throw MCPPortfolioRequestError.invalid("Invalid readPolicy")
            }
            guard let cursor = raw as? String, UUID(uuidString: cursor) != nil else {
                throw MCPPortfolioRequestError(code: "INVALID_CURSOR", message: "Invalid cursor; start a new summary")
            }
            return .continuation(cursor: cursor, policy: arguments["readPolicy"] == nil ? nil : policy)
        }
        guard Set(arguments.keys).isSubset(of: ["start", "end", "limit", "projectId", "project", "readPolicy"]),
              let start = arguments["start"] as? String, let end = arguments["end"] as? String,
              let limit = IntentHelpers.parseIntValue(arguments["limit"]), (1...100).contains(limit),
              let policy = MCPReadRefreshPolicy.parse(arguments["readPolicy"]) else {
            throw MCPPortfolioRequestError.invalid(
                "Supply start, end and integer limit from 1 through 100; use supported fields")
        }
        guard arguments["projectId"] == nil || arguments["project"] == nil else {
            throw MCPPortfolioRequestError.invalid("Use only one project selector")
        }
        let selector = try projectSelector(arguments)
        let window: CompletionWindow
        do { window = try CompletionWindow.parse(start: start, end: end) } catch {
            throw MCPPortfolioRequestError.invalid(
                "Invalid completion window; supply explicit timezone timestamps with start before end")
        }
        return .initial(window: window, limit: limit, project: selector, policy: policy)
    }

    @MainActor private static func projectSelector(_ arguments: [String: Any]) throws -> ReadProjectSelector? {
        if let raw = arguments["projectId"] {
            guard let string = raw as? String, let id = UUID(uuidString: string) else {
                throw MCPPortfolioRequestError.invalid("projectId must be a UUID string")
            }
            return .id(id)
        }
        if let raw = arguments["project"] {
            guard let name = raw as? String, !ProjectNamePolicy.normalized(name).isEmpty else {
                throw MCPPortfolioRequestError.invalid("project must be a nonempty name")
            }
            // Resolution is exclusively the fenced capture provider's responsibility.
            return .name(name)
        }
        return nil
    }
}

extension CompletionWindow {
    nonisolated static func parse(start: String, end: String) throws -> Self {
        let startDate = try instant(start)
        let endDate = try instant(end)
        guard startDate < endDate else { throw CompletionWindowError.invalidInput }
        return Self(start: startDate, end: endDate)
    }

    nonisolated private static func instant(_ string: String) throws -> Date {
        let pattern = "^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})"
            + "(?:\\.([0-9]{1,3}))?(Z|[+-][0-9]{2}:[0-9]{2})$"
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(string.startIndex..., in: string)
        guard let match = expression.firstMatch(in: string, range: range), match.range == range else {
            throw CompletionWindowError.invalidInput
        }
        func field(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: string) else { return "" }
            return String(string[range])
        }
        let numbers = (1...6).compactMap { Int(field($0)) }
        guard numbers.count == 6, (1...9999).contains(numbers[0]), (1...12).contains(numbers[1]),
              (1...31).contains(numbers[2]), (0...23).contains(numbers[3]),
              (0...59).contains(numbers[4]), (0...59).contains(numbers[5]) else {
            throw CompletionWindowError.invalidInput
        }
        let zone = field(8)
        var offset = 0
        if zone != "Z" {
            let hours = Int(zone.dropFirst().prefix(2)) ?? 24
            let minutes = Int(zone.suffix(2)) ?? 60
            guard hours < 24, minutes < 60 else { throw CompletionWindowError.invalidInput }
            offset = (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2],
                                        hour: numbers[3], minute: numbers[4], second: numbers[5])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components else {
            throw CompletionWindowError.invalidInput
        }
        let fraction = field(7)
        let fractionalSeconds = fraction.isEmpty ? 0 : (Double("0.\(fraction)") ?? 0)
        return date.addingTimeInterval(fractionalSeconds - Double(offset))
    }
}
#endif
