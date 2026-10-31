// Compile the real extracted counter contract/CAS extension without SwiftData model macros or an app host.
// Only the allocator namespace and error names are stubs; no counter behavior is duplicated.
import Foundation
@MainActor enum DisplayIDAllocator {
    enum Error: Swift.Error { case conflict, retriesExhausted }
}

enum ContainerFactory {
    struct ContainerOutcome { let error: (any Error)? }
}
