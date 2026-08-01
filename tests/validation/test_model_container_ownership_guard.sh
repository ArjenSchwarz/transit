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

expect_rejected() {
    local fixture="$1"
    shift
    local output
    local status

    set +e
    output="$(python3 "$VALIDATOR" "$@" "$fixture" 2>&1)"
    status=$?
    set -e

    if [[ $status -ne 1 ]] || ! grep -q "ownership validation failed" <<<"$output"; then
        echo "$output" >&2
        fail "unsafe fixture did not produce an ownership violation: $(basename "$fixture") (exit $status)"
    fi
    pass "unsafe fixture rejected: $(basename "$fixture")"
}

python3 "$VALIDATOR" "$FIXTURES/accepted" >/dev/null \
    || fail "owning fixture and lexical literal forms should pass"
pass "owning fixture APIs and lexical literals pass"

for fixture in "$FIXTURES"/unsafe/*.swift.fixture; do
    expect_rejected "$fixture"
done

for fixture in "$FIXTURES"/support/accepted/*.swift.fixture; do
    python3 "$VALIDATOR" --support-file "$fixture" "$fixture" >/dev/null \
        || fail "valid support fixture unexpectedly failed: $(basename "$fixture")"
    pass "valid support fixture accepted: $(basename "$fixture")"
done

for fixture in "$FIXTURES"/support/unsafe/*.swift.fixture; do
    expect_rejected "$fixture" --support-file "$fixture"
done

python3 "$VALIDATOR" "$ROOT/Transit/TransitTests" >/dev/null \
    || fail "repository test sources violate the ownership boundary"
pass "repository test sources obey the centralized ownership boundary"

echo "All SwiftData ownership guard checks passed."
