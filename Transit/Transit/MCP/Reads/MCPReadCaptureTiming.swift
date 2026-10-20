#if os(macOS)
import Foundation

extension ReadCaptureRequest {
    /// No suspension or logging on the capture actor. The existing bounded sink receives scalars only.
    /// Begin before entering synchronous work so the independent timeout can name a blocked stage.
    @MainActor func measureCapture<Value>(_ phase: MCPReadDiagnosticPhase,
                                          _ body: () throws -> Value) rethrows -> Value {
        guard let operation = diagnosticOperation, operation.diagnosticsEnabled else { return try body() }
        operation.beginPhase(phase)
        let started = ContinuousClock.now
        defer { operation.beginPhase(.capture) }
        do {
            let value = try body()
            operation.recordDiagnostic(phase, startedAt: started, outcome: .success)
            return value
        } catch {
            // Do not retain or format the error; storage failures can contain private values.
            operation.recordDiagnostic(phase, startedAt: started, outcome: .failure)
            throw error
        }
    }
}
#endif
