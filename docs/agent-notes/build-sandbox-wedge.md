# Build/Test Sandbox Wedge (Claude Code background sessions)

## Symptom
`make build` / `make test` / `make test-quick` (anything invoking `xcodebuild`) hangs
**forever at 0% CPU with zero output**. The `xcodebuild test` process shows state
`SN` (sleeping, blocked) and never progresses — it looks identical to an
XCBBuildService crash or a system overload, but it is neither. One run sat wedged
for 19 hours.

## Root cause
The Claude Code session shell runs **sandboxed**, and the sandbox blocks
`xcodebuild`'s XPC connection to **XCBBuildService**. The build action blocks on
the handshake that never completes.

Tell-tale: things that do NOT need the build-service XPC work fine sandboxed —
`make lint` (SwiftLint), `xcodebuild -version`, `xcrun --find swiftc`. Only
`build`/`test` actions wedge.

## Fix
Run every build/test command with the Bash tool parameter
`dangerouslyDisableSandbox: true`. With the sandbox off, `make test-quick`
compiles and runs normally (~1300+ checks, "Test Succeeded").

When delegating build/test work to a subagent, tell it this explicitly — a subagent
that runs `make test-quick` the normal way will wedge for a long time. Safety valve:
if any build command produces no output for ~3 minutes, `pkill -9 -f xcodebuild` and
re-run with the sandbox disabled.

## What does NOT help (don't waste time on these)
Killing strays, clearing the module cache, wiping `DerivedData`, killing
XCBBuildService, quitting the Xcode GUI, reducing system load — none of it fixes the
wedge, because the wedge is the sandbox, not the build state. Repeatedly
`kill -9`-ing XCBBuildService can additionally trip launchd's respawn backoff and
make things look worse.

## Note on pipe exit codes
`make test-quick` pipes `xcodebuild ... | xcbeautify`. `xcbeautify` exits 0 even when
tests fail, so `$?`/`PIPESTATUS` after the pipe can read 0 on failure. Confirm
success by grepping the captured log for `Test Succeeded` vs `** TEST FAILED **` /
`Failing tests:`, not by exit code.
