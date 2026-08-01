#!/usr/bin/env bash
# Proves the T-2003 ownership guard rejects representative unsafe factory
# shapes and accepts APIs that carry the owning TestModelContainer fixture.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate_test_model_container_ownership.py"
FIXTURES="$ROOT/tests/fixtures/model_container_ownership"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    echo "PASS: $*"
}

python3 "$VALIDATOR" "$FIXTURES/accepted" >/dev/null \
    || fail "owning fixture forms should pass"
pass "owning fixture returns, tuples, and environments pass"

for fixture in "$FIXTURES"/unsafe/*.swift.fixture; do
    output="$(python3 "$VALIDATOR" "$fixture" 2>&1 || true)"
    if ! grep -q "ownership validation failed" <<<"$output"; then
        echo "$output" >&2
        fail "unsafe fixture unexpectedly passed: $(basename "$fixture")"
    fi
    pass "unsafe fixture rejected: $(basename "$fixture")"
done

python3 "$VALIDATOR" "$ROOT/Transit/TransitTests" >/dev/null \
    || fail "repository test sources violate the ownership boundary"
pass "repository test sources obey the centralized ownership boundary"

echo "All SwiftData ownership guard checks passed."
