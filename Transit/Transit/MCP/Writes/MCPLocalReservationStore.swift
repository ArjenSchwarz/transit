import Foundation
import CryptoKit
import Darwin

nonisolated struct MCPLocalReservation: Codable, Equatable, Sendable {
    var scopeID: String
    var tool: String
    var key: String
    var requestJSON: String
    var formatVersion: Int
    var receiptID: UUID
    var expiresAt: Date?
}

/// Only payload bindings live here; domain results commit with SwiftData.
@MainActor final class MCPLocalReservationStore {
    enum Error: Swift.Error, Equatable { case storeBusy, unreadable, keyReused, inconsistent }

    let scopeID: String
    private let directory: URL
    private let guardsDirectory: URL
    private let lockDescriptor: Int32
    private var phaseBindings: [BindingKey: MCPLocalReservation]?

    init(directory: URL) throws {
        self.directory = directory
        self.guardsDirectory = directory.appendingPathComponent("guards", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw Error.unreadable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw Error.storeBusy
        }
        self.lockDescriptor = descriptor
        do {
            try Self.completeReplacement(in: directory)
            let identityURL = directory.appendingPathComponent("scope")
            if FileManager.default.fileExists(atPath: identityURL.path) {
                let value = try String(contentsOf: identityURL, encoding: .utf8)
                guard let uuid = UUID(uuidString: value), value == uuid.uuidString.lowercased() else {
                    throw Error.inconsistent
                }
                scopeID = value
            } else {
                // A lost identity never creates a fresh namespace over old bindings.
                if FileManager.default.fileExists(atPath: guardsDirectory.path),
                   !(try FileManager.default.contentsOfDirectory(atPath: guardsDirectory.path)).isEmpty {
                    throw Error.inconsistent
                }
                let value = UUID().uuidString.lowercased()
                try Self.durableReplace(Data(value.utf8), at: identityURL)
                scopeID = value
            }
            try FileManager.default.createDirectory(at: guardsDirectory, withIntermediateDirectories: true)
            try Self.syncDirectory(directory)
            _ = try all()
        } catch {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            throw error
        }
    }

    deinit {
        flock(lockDescriptor, LOCK_UN)
        close(lockDescriptor)
    }

    /// Reuse one verified scope only while this synchronous body is running.
    /// The closure cannot await; every new phase validates the complete scope.
    func withValidatedBindings<T>(_ body: () throws -> T) throws -> T {
        if phaseBindings != nil { return try body() }
        var bindings: [BindingKey: MCPLocalReservation] = [:]
        for binding in try all() {
            guard bindings.updateValue(binding, forKey: BindingKey(binding)) == nil else { throw Error.inconsistent }
        }
        phaseBindings = bindings
        defer { phaseBindings = nil }
        return try body()
    }

    func lookup(tool: String, key: String) throws -> MCPLocalReservation? {
        let retiredURL = directory.appendingPathComponent("retired")
        if FileManager.default.fileExists(atPath: retiredURL.path) {
            let retired = try JSONDecoder().decode([String].self, from: Data(contentsOf: retiredURL))
            guard !retired.contains(file(tool: tool, key: key).lastPathComponent) else { throw Error.inconsistent }
        }
        if let phaseBindings { return phaseBindings[BindingKey(tool: tool, key: key)] }
        // Standalone calls still validate the complete scope, never just a target file.
        return try all().first { $0.tool == tool && $0.key == key }
    }

    func validateBinding(_ binding: MCPLocalReservation) throws {
        guard try lookup(tool: binding.tool, key: binding.key) == binding else { throw Error.inconsistent }
    }

    func reserve(tool: String, key: String, requestJSON: String, formatVersion: Int = 1,
                 receiptID: UUID = UUID()) throws -> MCPLocalReservation {
        if let existing = try lookup(tool: tool, key: key) {
            guard existing.requestJSON == requestJSON && existing.formatVersion == formatVersion else {
                throw Error.keyReused
            }
            return existing
        }
        guard !tool.isEmpty, !key.isEmpty, formatVersion == 1 else { throw Error.inconsistent }
        try validatePayload(requestJSON)
        let reservation = MCPLocalReservation(scopeID: scopeID, tool: tool, key: key,
                                              requestJSON: requestJSON, formatVersion: formatVersion,
                                              receiptID: receiptID)
        try persist(reservation)
        return reservation
    }

    func recordExpiry(_ reservation: MCPLocalReservation, expiresAt: Date) throws {
        guard var saved = try lookup(tool: reservation.tool, key: reservation.key),
              saved.receiptID == reservation.receiptID, saved.requestJSON == reservation.requestJSON,
              expiresAt.timeIntervalSinceReferenceDate.isFinite else { throw Error.inconsistent }
        if let original = saved.expiresAt {
            guard original == expiresAt else { throw Error.inconsistent }
            return
        }
        saved.expiresAt = expiresAt
        try persist(saved)
    }

    func removeExpired(now: Date) throws {
        for reservation in try all() {
            guard let expiry = reservation.expiresAt, expiry <= now else { continue }
            try remove(reservation)
        }
    }

    /// The process lock and MainActor keep this verified snapshot stable for the
    /// whole maintenance pass. Validate every binding before changing any file.
    func reconcileTerminalBindings(_ terminal: [MCPLocalReservation], now: Date) throws {
        var snapshot: [BindingKey: MCPLocalReservation] = [:]
        for binding in try all() {
            guard snapshot.updateValue(binding, forKey: BindingKey(binding)) == nil else { throw Error.inconsistent }
        }
        for binding in terminal {
            guard binding.scopeID == scopeID, binding.formatVersion == 1,
                  let expiry = binding.expiresAt, expiry.timeIntervalSinceReferenceDate.isFinite else {
                throw Error.inconsistent
            }
            if let saved = snapshot[BindingKey(binding)] {
                guard saved.receiptID == binding.receiptID, saved.requestJSON == binding.requestJSON,
                      saved.formatVersion == binding.formatVersion,
                      saved.expiresAt == nil || saved.expiresAt == expiry else { throw Error.inconsistent }
            }
        }
        for binding in terminal {
            let key = BindingKey(binding)
            if snapshot[key]?.expiresAt == nil { try persist(binding) }
            snapshot[key] = binding
        }
        for binding in snapshot.values where binding.expiresAt.map({ $0 <= now }) == true {
            try remove(binding)
        }
    }

    private struct ReplacementMarker: Codable {
        var newScope: String
        var retiredNames: [String]
    }

    /// Durable intent precedes the database save. All old keys are hashed tombstones.
    func stageDatabaseReplacement() throws {
        let names = try FileManager.default.contentsOfDirectory(at: guardsDirectory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".pending-") }.map(\.lastPathComponent)
        let marker = ReplacementMarker(newScope: UUID().uuidString.lowercased(), retiredNames: names)
        try Self.durableReplace(JSONEncoder().encode(marker), at: directory.appendingPathComponent("replacement"))
    }

    func cancelDatabaseReplacement() throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent("replacement"))
        try Self.syncDirectory(directory)
    }

    /// Startup resumes this publication if the process stopped after the database save.
    func rotateAfterDatabaseReplacement() throws { try Self.completeReplacement(in: directory) }

    private static func completeReplacement(in directory: URL) throws {
        let markerURL = directory.appendingPathComponent("replacement")
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let marker = try JSONDecoder().decode(ReplacementMarker.self, from: Data(contentsOf: markerURL))
        guard UUID(uuidString: marker.newScope)?.uuidString.lowercased() == marker.newScope else {
            throw Error.inconsistent
        }
        let retiredURL = directory.appendingPathComponent("retired")
        let existing = FileManager.default.fileExists(atPath: retiredURL.path)
            ? try JSONDecoder().decode([String].self, from: Data(contentsOf: retiredURL)) : []
        try durableReplace(JSONEncoder().encode(Array(Set(existing + marker.retiredNames)).sorted()), at: retiredURL)
        let guards = directory.appendingPathComponent("guards")
        for file in try FileManager.default.contentsOfDirectory(at: guards, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        try syncDirectory(guards)
        try durableReplace(Data(marker.newScope.utf8), at: directory.appendingPathComponent("scope"))
        try FileManager.default.removeItem(at: markerURL)
        try syncDirectory(directory)
    }

    struct BindingKey: Hashable {
        let tool: String
        let key: String

        init(_ binding: MCPLocalReservation) {
            tool = binding.tool
            key = binding.key
        }

        init(tool: String, key: String) {
            self.tool = tool
            self.key = key
        }
    }

    func all() throws -> [MCPLocalReservation] {
        if let phaseBindings { return Array(phaseBindings.values) }
        let files = try FileManager.default.contentsOfDirectory(at: guardsDirectory,
                                                               includingPropertiesForKeys: nil)
        return try files.map { url in
            // Temp files can survive a crash before rename: ignore only our
            // incomplete replacement files; they never prove acceptance.
            if url.lastPathComponent.hasPrefix(".pending-") { return nil }
            let value = try JSONDecoder().decode(MCPLocalReservation.self, from: Data(contentsOf: url))
            guard value.scopeID == scopeID, value.formatVersion == 1, !value.tool.isEmpty, !value.key.isEmpty,
                  url.lastPathComponent == file(tool: value.tool, key: value.key).lastPathComponent,
                  value.expiresAt?.timeIntervalSinceReferenceDate.isFinite != false else { throw Error.inconsistent }
            try validatePayload(value.requestJSON)
            return value
        }.compactMap { $0 }
    }

    private func validatePayload(_ json: String) throws {
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              try MCPCanonicalJSON.encode(object) == json else { throw Error.inconsistent }
    }

    private func persist(_ reservation: MCPLocalReservation) throws {
        do {
            try Self.durableReplace(JSONEncoder().encode(reservation),
                                    at: file(tool: reservation.tool, key: reservation.key))
            phaseBindings?[BindingKey(reservation)] = reservation
        } catch {
            // A failed durability check can follow rename. Never reuse an old
            // snapshot after a mutation whose durable result is ambiguous.
            phaseBindings = nil
            throw error
        }
    }

    private func remove(_ reservation: MCPLocalReservation) throws {
        do {
            try FileManager.default.removeItem(at: file(tool: reservation.tool, key: reservation.key))
            try Self.syncDirectory(guardsDirectory)
            phaseBindings?.removeValue(forKey: BindingKey(reservation))
        } catch {
            phaseBindings = nil
            throw error
        }
    }

    private func file(tool: String, key: String) -> URL {
        let input = Data((tool + "\u{0000}" + key).utf8)
        let name = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        return guardsDirectory.appendingPathComponent(name + ".json")
    }

    private static func durableReplace(_ data: Data, at url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".pending-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        let descriptor = open(temporary.path, O_RDWR)
        guard descriptor >= 0 else { throw Error.unreadable }
        defer { close(descriptor) }
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else { throw Error.unreadable }
        guard rename(temporary.path, url.path) == 0 else { throw Error.unreadable }
        try syncDirectory(url.deletingLastPathComponent())
    }

    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw Error.unreadable }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw Error.unreadable }
    }
}
