# T-2377 change explanation

## Beginner level

An MCP client can now create a Transit project before adding its tasks. It supplies a name and a color, plus an optional description and repository. Transit checks those values, saves the project, and returns its ID and details. The client can use that ID in its next create_task call.

The Mac's current Xcode toolchain also needs a newer dependency and clearer concurrency declarations. These changes allow the app and its existing actor-based tests to compile with Swift 6.4.

## Intermediate level

The core tool inventory and dispatcher now expose create_project. The handler validates required/optional string types and whole-string six-digit ASCII hex colors, then delegates trimmed-name validation, case-insensitive duplicate detection and persistence to ProjectService. A shared metadata formatter keeps get_projects and creation results aligned; discovery still enriches projects with milestones.

The dependency update changes only AsyncAlgorithms to 1.1.3. CounterStore and CounterSnapshot explicitly opt out of the application's MainActor default and use checked Sendable. Two existing test actors move their protocol conformances into empty extensions to avoid a Swift 6.4 declaration-order diagnostic. Their methods and state remain unchanged. A source-literal guard now runs as CLI preflight for lint/test commands, while the runtime description test remains cross-platform; app test runners do not open host checkout paths.

## Expert level

Creation remains a synchronous MainActor service operation, so local uniqueness validation and saving have no suspension window. Storage fallback rejects the new mutation through the existing gate. Invalid optional values, including JSON null, are rejected rather than silently discarded. Color validation checks the full regex range to reject trailing newlines; the stored color's case and prefix are preserved. Optional repository values retain the existing free-form service contract.

The response includes a persisted UUID usable by create_task. Tests cover schema discovery, validation, duplicate/read failure, metadata parity, persistence and project-to-task integration. Save-failure cleanup remains covered by the shared persistence helper rather than a new handler-specific failure seam.

The compatibility change preserves production CloudKitCounterStore's MainActor isolation and existing allocator serialization, retries and compare-and-swap behavior. Normal-order compiler reproduction and Xcode MCP build-for-testing validate the conformance-placement workaround; final runtime outcomes are recorded in implementation.md. No publication or deployment is included.
