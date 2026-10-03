import Foundation

@main
struct MCPWriteGuardProbe {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        if CommandLine.arguments[1] == "hold" {
            let store = try MCPLocalReservationStore(directory: directory)
            _ = try store.reserve(tool: "create_task", key: "key", requestJSON: "{}")
            print("LOCKED")
            fflush(stdout)
            _ = readLine()
            withExtendedLifetime(store) {}
        } else if CommandLine.arguments[1] == "busy" {
            do {
                _ = try MCPLocalReservationStore(directory: directory)
                fatalError("Second process acquired lock")
            } catch MCPLocalReservationStore.Error.storeBusy { print("BUSY") }
        } else if CommandLine.arguments[1] == "corrupt" {
            do {
                _ = try MCPLocalReservationStore(directory: directory)
                fatalError("Corrupt scope enabled writes")
            } catch { print("FAIL_CLOSED") }
        } else {
            let store = try MCPLocalReservationStore(directory: directory)
            let record = try store.lookup(tool: "create_task", key: "key")
            precondition(record != nil)
            try store.removeExpired(now: Date.distantFuture)
            let unresolved = try store.lookup(tool: "create_task", key: "key")
            precondition(unresolved == record)
            do {
                _ = try store.reserve(tool: "create_task", key: "key", requestJSON: "{\"x\":1}")
                fatalError("Mismatched payload accepted")
            } catch MCPLocalReservationStore.Error.keyReused {}
            let terminal = try store.reserve(tool: "create_project", key: "terminal", requestJSON: "{}")
            let expiry = Date(timeIntervalSinceReferenceDate: 604800)
            try store.recordExpiry(terminal, expiresAt: expiry)
            try store.recordExpiry(terminal, expiresAt: expiry)
            do {
                try store.recordExpiry(terminal, expiresAt: expiry.addingTimeInterval(1))
                fatalError("Deadline changed")
            } catch MCPLocalReservationStore.Error.inconsistent {}
            try store.removeExpired(now: expiry.addingTimeInterval(-1))
            let before = try store.lookup(tool: "create_project", key: "terminal")
            precondition(before != nil)
            try store.removeExpired(now: expiry)
            let after = try store.lookup(tool: "create_project", key: "terminal")
            precondition(after == nil)
            print("RECOVERED")
        }
    }
}
