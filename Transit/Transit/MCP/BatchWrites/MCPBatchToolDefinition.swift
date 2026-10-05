#if os(macOS)
import Foundation

nonisolated enum MCPBatchToolDefinition {
    static let description = """
        Preview or execute 1–50 ordered task mutations (update_task, update_task_status, add_comment). \
        Dry runs observe saved local storage only: advisory=true and keyState=unchecked. \
        Execute commits independently per item and stops at the first noncommitted or unestablished result. \
        Every item needs its own original protected-tool key and task UUID; update operations need expectedRevision. \
        Retry using identical original item arguments and keys in the originating store. No whole-batch transaction \
        or automatic retry exists. Historical receipt replay does not certify current contents. \
        Uncertain effects or serialization_failed require original-key reconciliation, never fresh-key retries.
        """

    // Typed core definitions remain the source for standalone argument validators.
    // Latest-only modern discovery substitutes the complete rich batch schema.
    static let definition = MCPToolDefinition(name: "mutate_tasks", description: description,
        inputSchema: .object(properties: [
            "mode": .stringEnum("Explicit mode", values: ["dry_run", "execute"]),
            "items": .array("1–50 uniquely targeted ordered mutations", itemType: "object")
        ], required: ["mode", "items"]))
}
#endif
