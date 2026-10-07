import Foundation

extension MCPReadCoordinator {
    /// Native values use the same physical permits, original clock and terminal selection.
    @concurrent func executeValue<Value: Codable & Sendable>(
        unavailable: Value, admittedAt: ContinuousClock.Instant = .now,
        admission: MCPReadAdmission = MCPReadAdmission(owner: .native),
        worker: @escaping @Sendable (MCPReadOperation) async throws -> Value
    ) async -> Value {
        guard let fallback = try? JSONEncoder().encode(unavailable) else { return unavailable }
        let bytes = await execute(timeout: fallback, busy: fallback, admittedAt: admittedAt, admission: admission,
            diagnosticTool: "native_consolidation_history") { operation in
                let encoded: Data
                do { encoded = try JSONEncoder().encode(await worker(operation)) } catch { encoded = fallback }
                return PreparedReadResult(encodedResponse: encoded, publications: [],
                    publicationErrors: PreencodedPublicationErrors(busy: fallback, expired: fallback,
                        capacity: fallback))
            }
        return (try? JSONDecoder().decode(Value.self, from: bytes)) ?? unavailable
    }
}
