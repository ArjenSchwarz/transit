# Isolated Xcode 27 design probes

These files are under the spec directory and are not included in Transit app targets. They are experiments for design approval, not authorized production implementation. Compile with installed Xcode27's Swift6.4 and SDK; build products/stores remain outside Git in the workspace's `t63-design-prototype` directory.

```sh
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -module-cache-path /Users/arjen/Documents/Codex/2026-10-03/task/t63-design-prototype/module-cache specs/bounded-read-freshness/prototype/DeadlineProbe.swift -o /Users/arjen/Documents/Codex/2026-10-03/task/t63-design-prototype/deadline-probe
/Users/arjen/Documents/Codex/2026-10-03/task/t63-design-prototype/deadline-probe
```

Final measured output (exit 0):

```text
MEASURE batch_ms=4851.153 response_ms=[4850.438959, 4850.478667, 4850.48225, 4850.484125, 4850.486459, 4850.488209, 4850.489584, 4850.490917] unfinished=8
PASS blocked_mainactor_ms=6000 encoded_batch_ms=4851.15 max_response_ms=4850.49 unfinished_at_timeout=8 unfinished_after_completion=0 late_publications=0 restart_busy=true bytes=809
```

An initial generic asyncAfter timer failed the five-second assertion at 5163.999 ms despite a 4850 ms deadline. Strict DispatchSourceTimer, zero leeway, userInitiated queue, explicit @concurrent async helpers, direct gate completion, and internal headroom produced the measured pass. macOS scheduling is not hard real-time; the app/transport load checks must measure encoded response availability at router return. This experiment does not validate real HTTP delivery, SwiftData fetches, lifecycle integration, actual retained store transactions, or arbitrary payload sizes. Publication and restart are modeled counters/gates, not production stores.

CaptureProbe uses two isolated on-disk SwiftData models with CloudKit disabled. The same compile command applies with `CaptureProbe.swift` and output `capture-probe`; run it with a fresh `probe.store` path. SwiftData compiler macro initialization required supported scoped per-command escalation; no compiler safeguards were disabled. Its successful run printed:

```text
PASS mixed_capture_rejected=true fresh_saved_write_visible=true stable_history_watermark=true store_identifier_known=true mixed_values=["old", "new"] stable_values=["new", "new"]
```

Two Core Data store-notification registration diagnostics appeared in the restricted runtime; the probe exited 0. It verifies public persistent-history tokens can reject a saved change across two selected fetches and fresh context sees saved state. It does not prove live CloudKit history/event-store correlation, history completeness during remote imports, or shared UI pending-edit behavior. Those remain early design verification gates.

The parallel T2382 worker independently measured a strict 4.95-second timer selecting timeout bytes at 4.950227 seconds with six-second MainActor blocking, eight retained permits, and 120 single-winner race cases. Its original exact-five-second strict timer measured 5.000345 seconds; its generic asyncAfter timer measured 5.333136 seconds. Both prototypes support independent coordination with internal headroom, not a hard-real-time scheduler claim.
