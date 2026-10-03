---
paths:
  - "**/*.swift"
---

# SwiftData Task Results

- Do not return a SwiftData `@Model` from a child `Task`: `Task.value` requires a Sendable result, and SwiftData explicitly rejects model Sendable conformance.
- Return a UUID, an immutable Sendable value, or `Void`; keep model access and re-resolution on the owning actor/context.
- Do not add `@unchecked Sendable` to persistent models to bypass this check. Regression tests must preserve the intended suspension/cancellation behavior while using a safe result boundary.
