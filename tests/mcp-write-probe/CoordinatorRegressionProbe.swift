import Foundation
import SwiftData

extension MCPWriteCoordinatorProbe {
    @MainActor static func phaseSuspension(services: MCPWriteCommandServices, directory: URL) async throws {
        let sidecar = directory.appendingPathComponent("phase-suspension")
        let gate = CoordinatorGate()
        let coordinator = MCPWriteCoordinator(
            services: services, sidecarDirectory: sidecar,
            preparationHook: { command in if command.key == "suspended" { await gate.park() } })
        let args: [String: Any] = ["name": "suspended", "colorHex": "#112233", "idempotencyKey": "suspended"]
        let running = Task { await coordinator.execute(tool: "create_project", arguments: args) }
        await gate.waitForStart()
        let peer = try decode(
            await coordinator.execute(
                tool: "create_project",
                arguments: ["name": "phase peer", "colorHex": "#112233", "idempotencyKey": "peer"]))
        precondition(peer["outcome"] as? String == "committed")
        try Data("corrupted".utf8).write(to: sidecar.appendingPathComponent("guards/corrupt.json"))
        await gate.release()
        let result = try decode(await running.value)
        precondition(result["outcome"] as? String == "uncertain")
        precondition((result["error"] as? [String: Any])?["code"] as? String == "OUTCOME_UNCERTAIN")
        let projects = try services.context.fetch(FetchDescriptor<Project>())
        precondition(!projects.contains { $0.name == "suspended" })
        let receipt = try services.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first {
            $0.key == "suspended"
        }!
        precondition(receipt.stateRawValue == "accepted" && receipt.resultJSON == nil)
        let retry = try decode(await coordinator.execute(tool: "create_project", arguments: args))
        precondition(retry["outcome"] as? String == "uncertain")
        print("PASS independent concurrent phases and scope-corruption revalidation after suspension")
    }

    @MainActor static func integerBoundaries() {
        let args: [String: Any] = ["displayId": Int.max, "content": "C", "authorName": "A", "idempotencyKey": "max"]
        precondition((try? MCPWriteCommand.validate(tool: "add_comment", arguments: args)) != nil)
        for value in [true, 1.5, Double(Int.max), NSNumber(value: UInt64.max)] as [Any] {
            var invalid = args
            invalid["displayId"] = value
            precondition((try? MCPWriteCommand.validate(tool: "add_comment", arguments: invalid)) == nil)
        }
        print("PASS exact Int.max acceptance and strict boolean/fraction/out-of-range rejection")
    }

    // swiftlint:disable:next function_body_length
    @MainActor static func malformedTerminals(services: MCPWriteCommandServices, directory: URL) async throws {
        let coordinator = MCPWriteCoordinator(
            services: services, sidecarDirectory: directory.appendingPathComponent("malformed"))
        let projectArgs: [String: Any] = [
            "name": "malformed P", "colorHex": "#112233", "idempotencyKey": "malformed-project"
        ]
        let project = try decode(await coordinator.execute(tool: "create_project", arguments: projectArgs))
        let task = try await services.tasks.createTask(
            name: "malformed T", description: nil, type: .feature,
            project: services.projects.findProject(id: UUID(uuidString: project["entityId"] as? String ?? "")!)
                .get())
        let statusArgs: [String: Any] = [
            "taskId": task.id.uuidString, "status": "done", "comment": "C",
            "authorName": "A", "expectedRevision": try MCPRecordSnapshot.task(task, in: services.context).revision,
            "idempotencyKey": "malformed-status"
        ]
        let status = try decode(await coordinator.execute(tool: "update_task_status", arguments: statusArgs))
        var conflictArgs = statusArgs
        conflictArgs["idempotencyKey"] = "malformed-conflict"
        let conflict = try decode(await coordinator.execute(tool: "update_task_status", arguments: conflictArgs))
        let milestone = try await services.milestones.createMilestone(
            name: "malformed M", description: nil, project: task.project!)
        let deleteArgs: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "expectedRevision": try MCPRecordSnapshot.milestone(milestone).revision,
            "idempotencyKey": "malformed-delete"
        ]
        let deletion = try decode(await coordinator.execute(tool: "delete_milestone", arguments: deleteArgs))
        let rejectArgs: [String: Any] = [
            "name": "reject", "colorHex": "invalid", "idempotencyKey": "malformed-reject"
        ]
        let rejection = try decode(await coordinator.execute(tool: "create_project", arguments: rejectArgs))
        let cases: [((String, [String: Any]), ([String: Any], [String]))] = [
            (
                ("create_project", projectArgs),
                (
                    project,
                    [
                        "entityId", "record", "record.revision", "record.name", "completedAt", "replayExpiresAt",
                        "completedAtMismatch", "entityIdMismatch"
                    ]
                )
            ),
            (
                ("update_task_status", statusArgs),
                (status, ["record.comments", "record.creationDate", "comment", "comment.revision"])
            ),
            (
                ("delete_milestone", deleteArgs),
                (deletion, ["deleted", "recordBeforeDeletion", "recordBeforeDeletion.revision"])
            ),
            (("update_task_status", conflictArgs), (conflict, ["currentRecord", "currentRecord.revision"])),
            (("create_project", rejectArgs), (rejection, ["error", "error.code", "error.message", "retryAction"]))
        ]
        for ((tool, args), (original, fields)) in cases {
            let receipt = try services.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first {
                $0.key == args["idempotencyKey"] as? String
            }!
            let saved = receipt.resultJSON!
            for field in fields {
                var malformed = original
                let components = field.split(separator: ".").map(String.init)
                if field == "completedAtMismatch" {
                    malformed["completedAt"] = MCPRecordSnapshot.timestamp(.distantPast)
                } else if field == "entityIdMismatch" {
                    malformed["entityId"] = UUID().uuidString
                } else if components.count == 2 {
                    var record = malformed[components[0]] as? [String: Any] ?? [:]
                    record.removeValue(forKey: components[1])
                    malformed[components[0]] = record
                } else {
                    malformed.removeValue(forKey: field)
                }
                let malformedJSON = try MCPWriteOutcome.encode(malformed)
                receipt.resultJSON = malformedJSON
                try services.context.save()
                let result = try decode(await coordinator.execute(tool: tool, arguments: args))
                precondition(result["outcome"] as? String == "uncertain")
                precondition((result["error"] as? [String: Any])?["code"] as? String == "OUTCOME_UNCERTAIN")
                precondition(result["retryAction"] as? String == "reconcile")
                precondition(receipt.resultJSON == malformedJSON)
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory.appendingPathComponent("malformed/guards"),
                    includingPropertiesForKeys: nil)
                let bindings = try files.filter { $0.pathExtension == "json" }.map {
                    try JSONDecoder().decode(MCPLocalReservation.self, from: Data(contentsOf: $0))
                }
                precondition(bindings.contains { $0.tool == tool && $0.key == args["idempotencyKey"] as? String })
            }
            receipt.resultJSON = saved
            try services.context.save()
            let replay = try decode(await coordinator.execute(tool: tool, arguments: args))
            let identical = try MCPCanonicalJSON.encode(replay) == MCPCanonicalJSON.encode(original)
            precondition(identical)
        }
        print(
            "PASS malformed terminal records/deletion/status-comment return uncertainty and retain receipts"
        )
    }

}
