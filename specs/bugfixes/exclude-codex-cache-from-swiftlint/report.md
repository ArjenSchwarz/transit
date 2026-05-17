# Bugfix Report: Exclude .codex-cache from SwiftLint

**Date:** 2026-05-17
**Status:** Fixed
**Transit ticket:** T-1158

## Description of the Issue

`make lint` allowed SwiftLint to scan workspace-local automation/cache files under `.codex-cache`. The project's `.swiftlint.yml` excluded only `DerivedData` and `specs`, so any Swift files dropped into `.codex-cache/tmp/*` (e.g. by the codex automation harness) were linted as if they were project sources.

**Reproduction steps:**
1. Create `.codex-cache/tmp/TemporaryDirectory.XXXX/main.swift` containing intentionally short identifier names and a long line (representative of what codex automation generates).
2. Run `swiftlint lint --strict --no-cache` (or `make lint`).
3. Observe identifier-name and line-length violations reported against files under `.codex-cache/`.

**Impact:** Low severity, automation-blocking. `make lint` fails on generated temp files that have nothing to do with project source. This was observed during the 2026-05-07 automation run on `.codex-cache/tmp/TemporaryDirectory.HXK5fW/main.swift` and `.codex-cache/tmp/TemporaryDirectory.gA1WSk/main.swift`. The workspace-local SwiftLint cache permission failure tracked by T-951/T-1130 is a separate concern.

## Investigation Summary

- **Symptoms examined:** SwiftLint reporting `identifier_name` and `line_length` violations in files under `.codex-cache/tmp/`.
- **Code inspected:** `.swiftlint.yml` (only file that controls scan scope), `Makefile` (`lint` target just calls `swiftlint lint --strict`).
- **Hypotheses tested:** Whether SwiftLint was being invoked with extra paths (no — Makefile uses the default discovery); whether `.codex-cache` was tracked in git (no — but SwiftLint discovers files on disk regardless of git status). The root cause was the missing exclusion entry.

## Discovered Root Cause

The `.swiftlint.yml` file's `excluded` list did not include `.codex-cache`. SwiftLint walks the working directory recursively and lints any `*.swift` file that is not under an excluded path. Workspace-local cache directories created by automation (codex temp dirs) therefore got scanned.

**Defect type:** Configuration omission.

**Why it occurred:** The codex automation harness writes temporary Swift files into a workspace-local cache directory (`.codex-cache/tmp/...`) that did not exist when the original `.swiftlint.yml` exclusion list was written.

**Contributing factors:** SwiftLint's default behaviour is to discover Swift files via filesystem walk, not via git index, so untracked cache files are still subject to linting unless explicitly excluded.

## Resolution for the Issue

**Changes made:**
- `.swiftlint.yml:2` — added `.codex-cache` entry to the `excluded` list (sorted alphabetically before `DerivedData`).

**Approach rationale:** Matches the existing pattern (`DerivedData`, `specs`) and is the minimal, targeted change. SwiftLint exclusion paths are relative to the working directory, so a single entry covers the whole subtree.

**Alternatives considered:**
- Use `included:` instead of `excluded:` to whitelist project source directories — rejected as a much larger configuration change that would require listing every Swift-containing directory and re-listing them whenever the project grows.
- Move SwiftLint cache out of the workspace (T-951/T-1130 territory) — rejected as out of scope; that ticket is tracked separately and addresses a different symptom.

## Regression Test

This is a configuration-only change to a YAML file, so there is no unit test added. The bug was reproduced manually before the fix and verified manually after the fix:

**Reproduction (pre-fix):**
```bash
mkdir -p .codex-cache/tmp/TemporaryDirectory.HXK5fW
cat > .codex-cache/tmp/TemporaryDirectory.HXK5fW/main.swift <<'EOF'
let x = "..."   # short identifier + long line
let y_bad_name = 1
EOF
swiftlint lint --strict --no-cache
# Before fix: identifier_name + line_length violations reported on .codex-cache files
# After fix:  Done linting! Found 0 violations, 0 serious in 217 files.
```

The "regression test" is therefore the fact that `make lint` continues to pass while `.codex-cache` is on disk. Any future regression (e.g. someone removing the entry) would be caught by the next CI/automation run that has cache files present.

## Affected Files

| File | Change |
|------|--------|
| `.swiftlint.yml` | Added `.codex-cache` to the `excluded` list |
| `specs/bugfixes/exclude-codex-cache-from-swiftlint/report.md` | Added this bugfix report |

## Verification

**Automated:**
- [x] `swiftlint lint --strict --no-cache` reports zero violations with `.codex-cache` present
- [x] `make lint` passes
- [x] Lint scans 217 project files (unchanged); `.codex-cache` files are silently skipped

**Manual verification:**
- Created representative `.codex-cache/tmp/.../main.swift` fixture with intentional violations; confirmed pre-fix reported violations against those files and post-fix did not.

## Prevention

**Recommendations to avoid similar bugs:**
- When introducing a new workspace-local cache or temp directory under the repo root, immediately add it to both `.gitignore` and any tool exclusion lists (`.swiftlint.yml`, etc.).
- Consider documenting workspace-local cache locations in `docs/agent-notes/` so they are easy to keep in sync with tool configs.

## Related

- T-1158 — this bug
- T-951 / T-1130 — SwiftLint cache permission failure (separate, kept distinct per ticket description)
