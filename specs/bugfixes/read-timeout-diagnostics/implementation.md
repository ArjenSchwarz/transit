# T-2455 implementation explanation

## Beginner

When a read times out, Transit now records how long this process has been running, which phase the request reached, and how long unfinished requests have occupied capacity. A separate writer saves a small rolling journal even while the app's main thread is blocked. It records measurements, not ticket contents. The journal makes a future incident easier to diagnose; it does not identify the cause of the reported uptime pattern.

## Intermediate

The coordinator tracks scalar phase transitions under its existing publication domain and snapshots at terminal selection or admission rejection. A process-start sample uses Darwin metadata once, followed by a monotonic clock. The bounded diagnostic queue favors failure summaries over ordinary queued debug events and records drops. Its utility writer atomically replaces a fixed-schema cache journal capped at 64 records/64KiB, with bounded reload and validation. Typed prepared read-failure metadata distinguishes busy/timeout without parsing error-message strings.

## Expert

No logger or disk work runs under the common publication lock or on MainActor. Timeout selection does not retire physical entries; oldest-worker age includes timed-out entries until their actual finalizer removes them. Each snapshot preserves the original generation and scalar terminal reason, including lifecycle invalidation while batch fallback bytes are not yet ready. Cache failures and saturation lose evidence without changing response/publication semantics. Successful detailed logs remain debug. Persisted records allowlist every string field and exclude operation/task identities and payloads. Cache eviction and sudden process termination can lose queued records; the journal is diagnostic evidence, not a durable audit. A queue/capture correlation cannot alone prove uptime causality or a sync/storage leak.

## Completeness assessment

Uptime, active-phase age, oldest unfinished physical-worker age, occupancy, lifecycle/cancellation/admission reasons, bounded retention and drop accounting are implemented. Focused regressions include persistence while MainActor blocks, retained busy evidence, deferred lifecycle classification, redaction, rollover and oversized/untrusted input retirement. Deployment, live long-uptime attribution and any underlying capture/sync fix remain outside this change.
