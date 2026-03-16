#!/usr/bin/env bash
# run-all.sh -- Run all harness-it integration tests
#
# Usage:
#   bash tests/run-all.sh           # Run all tests
#   bash tests/run-all.sh quick     # Skip Docker/LocalStack tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-full}"
SUITE_PASS=0
SUITE_FAIL=0

run_test() {
    local name="$1"
    local script="$2"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Running: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if bash "$script"; then
        SUITE_PASS=$((SUITE_PASS + 1))
    else
        SUITE_FAIL=$((SUITE_FAIL + 1))
    fi
}

echo "╔════════════════════════════════════════╗"
echo "║     harness-it Integration Tests       ║"
echo "╚════════════════════════════════════════╝"

# Always run unit-level tests
run_test "Config Loader Tests" "$SCRIPT_DIR/test-config-loader.sh"
run_test "Workflow Generator Tests" "$SCRIPT_DIR/test-workflow-gen.sh"

# Full mode includes the E2E smoke test
if [ "$MODE" = "full" ]; then
    run_test "End-to-End Smoke Test" "$SCRIPT_DIR/smoke-test-e2e.sh"
else
    echo ""
    echo "  [SKIP] End-to-End Smoke Test (quick mode)"
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║           Suite Summary                ║"
echo "╠════════════════════════════════════════╣"
SUITE_TOTAL=$((SUITE_PASS + SUITE_FAIL))
echo "║  $SUITE_PASS of $SUITE_TOTAL test suites passed              ║"
if [ $SUITE_FAIL -gt 0 ]; then
    echo "║  $SUITE_FAIL FAILED                              ║"
fi
echo "╚════════════════════════════════════════╝"

exit $SUITE_FAIL
