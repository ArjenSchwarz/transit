#if os(macOS)
import Foundation

nonisolated enum TaskLinkWireSchema {
    static let description = """
        Standalone task links accept at most 50 linkChanges directives. Add with action:add, exact type \
        blocks/blocked-by/relates-to/introduced-by/duplicate-of and targetTaskId UUID; remove with action:remove, \
        edgeId UUID and occurrenceRevision l1 token. Creation permits additions only. Endpoint preconditions are \
        unique taskId/expectedRevision r1 pairs for precisely other existing endpoints whose incidence changes; \
        no extra/source guards. Update always requires the source revision, including already-present no-ops. \
        Omission leaves links unchanged. Exact removal evidence permits original-selector no-op for seven days; \
        after expiry repair is unavailable. Same logical remove/add requires separate requests; duplicate retarget \
        may remove the old target and add a different target. Directions: blocks is outgoing dependency; blocked-by \
        incoming; relates-to symmetric; introduced-by and duplicate-of point from source to target. No redirection, \
        merge, status change or imported-writer fence. Only participating local coordinator writes share the owned \
        save; CloudKit imports and independent writers can later invalidate graph evidence. mutate_tasks \
        rejects linkChanges and endpointPreconditions before item acceptance.
        """

    static func changes(creating: Bool) -> JSONSchemaProperty {
        let add = closed(["action": .stringEnum("Add an occurrence", values: ["add"]),
                          "type": .stringEnum("Exact public relationship type",
                                              values: TaskLinkType.allCases.map(\.rawValue)),
                          "targetTaskId": uuid("Unambiguous saved target UUID")])
        let remove = closed(["action": .stringEnum("Remove an exact incident occurrence", values: ["remove"]),
                             "edgeId": uuid("Unique physical occurrence UUID"),
                             "occurrenceRevision": token("Exact immutable occurrence token", prefix: "l1")])
        let items = JSONSchemaItems(type: "object", enumValues: nil,
                                   oneOf: creating ? [add] : [add, remove])
        var property = JSONSchemaProperty(type: "array", description: description, enumValues: nil, items: items)
        property.maxItems = 50
        return property
    }

    static var endpoints: JSONSchemaProperty {
        let shape = closed(["taskId": uuid("Other existing affected endpoint UUID"),
                            "expectedRevision": token("Current graph-covered task token", prefix: "r1")])
        let items = JSONSchemaItems(type: "object", enumValues: nil, oneOf: [shape])
        var property = JSONSchemaProperty(type: "array",
                                          description: "Precisely other affected endpoints; no duplicates",
                                          enumValues: nil, items: items)
        property.maxItems = 50
        return property
    }

    private static func closed(_ properties: [String: JSONSchemaProperty]) -> JSONSchema {
        var schema = JSONSchema.object(properties: properties, required: properties.keys.sorted())
        schema.additionalProperties = false
        return schema
    }

    private static func uuid(_ description: String) -> JSONSchemaProperty {
        var field = JSONSchemaProperty.string(description)
        field.pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        return field
    }

    private static func token(_ description: String, prefix: String) -> JSONSchemaProperty {
        var field = JSONSchemaProperty.string(description)
        field.pattern = "^" + prefix + ":[0-9a-f]{64}$"
        return field
    }
}
#endif
