import Foundation
import Testing
@testable import Transit

@MainActor
struct TransitAppRuntimeTests {
    @Test
    func persistentStoreURLUsesStablePathAndCreatesDirectory() {
        let first = TransitAppRuntime.persistentStoreURL()
        let second = TransitAppRuntime.persistentStoreURL()

        #expect(first == second)
        #expect(first.lastPathComponent == "Transit.store")
        #expect(first.deletingLastPathComponent().lastPathComponent == "Transit")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: first.deletingLastPathComponent().path,
            isDirectory: &isDirectory
        )
        #expect(exists)
        #expect(isDirectory.boolValue)
    }
}
