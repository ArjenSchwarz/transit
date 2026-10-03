---
paths:
  - "**/*.swift"
---

# Swift JSON Number Identity

- Do not canonicalize JSON numbers through `NSNumber.decimalValue`: it can round distinct adjacent `Double` values together and overflow finite exponent values. This breaks payload identity for idempotency keys.
- Use a lossless numeric representation, keep Boolean values distinct from numbers, and preserve equality for equivalent parsed numeric encodings such as `1` and `1.0`.
- Cover adjacent representable doubles, finite exponent extremes, and integer/floating equivalents in canonicalization regressions.
