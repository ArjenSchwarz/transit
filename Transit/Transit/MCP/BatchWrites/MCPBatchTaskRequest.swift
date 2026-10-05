#if os(macOS)
import Foundation

/// Establishes the entire shape before callers can admit any item. No service
/// or write coordinator is reachable here; original JSON stays immutable.
@MainActor struct MCPBatchTaskRequest {
    enum Mode: String { case dryRun = "dry_run", execute }

    struct Item {
        let index: Int
        let itemId: String
        let operation: String
        let targetTaskId: UUID
        let originalArguments: MCPJSONValue
        let command: MCPWriteCommand
    }

    struct Diagnostic {
        let index: Int?
        let itemId: String?
        let field: String
        let code: String
    }

    enum Validation {
        case valid(MCPBatchTaskRequest)
        case invalid([Diagnostic])
    }

    let mode: Mode
    let items: [Item]

    private init(mode: Mode, items: [Item]) {
        self.mode = mode
        self.items = items
    }

    static func parse(_ document: MCPJSONDocument) throws -> Validation {
        try parse(validatedValue: document.value)
    }

    /// The shared modern owner can pass the original parsed arguments tree here
    /// before Any conversion. This avoids losing numeric tokens in a roundtrip.
    static func parse(validatedValue value: MCPJSONValue) throws -> Validation {
        guard case .object(let members) = value else { return invalid(field: "arguments") }
        if let field = MCPBatchTaskInputValue.closedField(members, allowed: ["mode", "items"]) {
            return invalid(field: field)
        }
        let mode: Mode
        let modeValue = MCPBatchTaskInputValue.string(MCPBatchTaskInputValue.member("mode", in: members))
        if modeValue?.utf8.elementsEqual("execute".utf8) == true {
            mode = .execute
        } else if modeValue?.utf8.elementsEqual("dry_run".utf8) == true {
            mode = .dryRun
        } else { return invalid(field: "mode") }
        guard case .array(let values) = MCPBatchTaskInputValue.member("items", in: members),
              (1...50).contains(values.count) else { return invalid(field: "items") }
        var items: [Item] = []
        var diagnostics: [Diagnostic] = []
        var identities = Identities()
        for (index, value) in values.enumerated() {
            switch try item(value, index: index) {
            case .invalid(let diagnostic): diagnostics.append(diagnostic)
            case .valid(let item):
                if let field = identities.insert(item) {
                    diagnostics.append(diagnostic(index: index, itemId: item.itemId, field: field))
                } else { items.append(item) }
            }
        }
        return diagnostics.isEmpty ? .valid(Self(mode: mode, items: items)) : .invalid(diagnostics)
    }

    private enum Candidate {
        case valid(Item)
        case invalid(Diagnostic)
    }

    private static func item(_ value: MCPJSONValue, index: Int) throws -> Candidate {
        guard case .object(let members) = value else {
            return .invalid(diagnostic(index: index, itemId: nil, field: "item"))
        }
        let itemId = MCPBatchTaskInputValue.string(MCPBatchTaskInputValue.member("itemId", in: members))
        let usableId = itemId.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        func rejected(_ field: String) -> Candidate {
            .invalid(diagnostic(index: index, itemId: usableId, field: field))
        }
        if let field = MCPBatchTaskInputValue.closedField(members, allowed: ["itemId", "operation", "arguments"]) {
            return rejected(field)
        }
        guard let usableId else { return rejected("itemId") }
        guard let operation = MCPBatchTaskInputValue.string(MCPBatchTaskInputValue.member("operation", in: members)),
              MCPBatchTaskSchema.operations.contains(where: { $0.utf8.elementsEqual(operation.utf8) }) else {
            return rejected("operation")
        }
        guard let originalArguments = MCPBatchTaskInputValue.member("arguments", in: members) else {
            return rejected("arguments")
        }
        switch try MCPBatchTaskInputArguments.validate(originalArguments, operation: operation) {
        case .invalid(let field): return rejected(field)
        case .valid(let arguments):
            do {
                let command = try MCPWriteCommand.validate(tool: operation, arguments: arguments)
                guard let taskId = (arguments["taskId"] as? String).flatMap(UUID.init(uuidString:)) else {
                    return rejected("taskId")
                }
                return .valid(Item(index: index, itemId: usableId, operation: operation,
                                   targetTaskId: taskId, originalArguments: originalArguments, command: command))
            } catch { return rejected("arguments") }
        }
    }

    nonisolated private struct ToolKey: Hashable {
        let operation: MCPBatchTaskInputIdentity
        let key: MCPBatchTaskInputIdentity
    }

    private struct Identities {
        var itemIds: Set<MCPBatchTaskInputIdentity> = []
        var taskIds: Set<UUID> = []
        var keys: Set<ToolKey> = []

        mutating func insert(_ item: Item) -> String? {
            guard itemIds.insert(MCPBatchTaskInputIdentity(value: item.itemId)).inserted else { return "itemId" }
            guard taskIds.insert(item.targetTaskId).inserted else { return "taskId" }
            let key = ToolKey(operation: MCPBatchTaskInputIdentity(value: item.operation),
                              key: MCPBatchTaskInputIdentity(value: item.command.key))
            return keys.insert(key).inserted ? nil : "idempotencyKey"
        }
    }

    private static func diagnostic(index: Int?, itemId: String?, field: String) -> Diagnostic {
        Diagnostic(index: index, itemId: itemId, field: field, code: "INVALID_INPUT")
    }

    private static func invalid(field: String) -> Validation {
        .invalid([diagnostic(index: nil, itemId: nil, field: field)])
    }
}
#endif
