#!/usr/bin/env bash
# test-config-loader.sh -- Validate ship-it config loader merge logic
#
# Creates fixture projects with various combinations of:
#   - .ship-it.yml (with/without infra)
#   - app-context.json (from /make-it)
#   - .make-it-state.md (build-verify status)
#   - Stack files (package.json, requirements.txt, etc.)
#
# Runs the config loader against each fixture and validates the output.
#
# Prerequisites:
#   - Node.js installed
#   - ship-it repo cloned alongside harness-it
#
# Usage:
#   bash tests/test-config-loader.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIP_IT_ROOT="$(cd "$HARNESS_ROOT/../ship-it" && pwd)"

# Verify ship-it repo exists
if [ ! -f "$SHIP_IT_ROOT/src/config-loader.js" ]; then
    echo "ERROR: ship-it repo not found at $SHIP_IT_ROOT"
    echo "Clone it: git clone https://github.com/sealmindset/ship-it.git alongside harness-it"
    exit 1
fi

# Check node_modules
if [ ! -d "$SHIP_IT_ROOT/node_modules" ]; then
    echo "Installing ship-it dependencies..."
    (cd "$SHIP_IT_ROOT" && npm install --silent)
fi

FIXTURES_DIR="$(mktemp -d)"
PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -rf "$FIXTURES_DIR"
}
trap cleanup EXIT

# Helper: run config loader on a fixture directory
run_loader() {
    local dir="$1"
    node -e "
        const { loadConfig } = require('$SHIP_IT_ROOT/src/config-loader');
        const config = loadConfig({ workingDir: '$dir' });
        console.log(JSON.stringify(config, null, 2));
    "
}

# Helper: assert a JSON path equals expected value
assert_eq() {
    local label="$1"
    local json="$2"
    local jq_path="$3"
    local expected="$4"
    TOTAL=$((TOTAL + 1))

    local actual
    actual=$(echo "$json" | node -e "
        const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
        const keys = '$jq_path'.split('.');
        let v = d;
        for (const k of keys) v = v?.[k];
        console.log(typeof v === 'object' ? JSON.stringify(v) : String(v));
    ")

    if [ "$actual" = "$expected" ]; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $label"
        echo "         expected: $expected"
        echo "         got:      $actual"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  ship-it Config Loader Integration Tests"
echo "============================================"
echo ""

# -----------------------------------------------------------
# Test 1: Empty project (no config files)
# -----------------------------------------------------------
echo "Test 1: Empty project (defaults only)"
DIR1="$FIXTURES_DIR/test1"
mkdir -p "$DIR1"

RESULT=$(run_loader "$DIR1")
assert_eq "app.name is empty" "$RESULT" "app.name" ""
assert_eq "infra.configured is false" "$RESULT" "infra.configured" "false"
assert_eq "context.hasMakeIt is false" "$RESULT" "context.hasMakeIt" "false"
assert_eq "context.hasShipItYml is false" "$RESULT" "context.hasShipItYml" "false"
echo ""

# -----------------------------------------------------------
# Test 2: Node.js project (auto-detection)
# -----------------------------------------------------------
echo "Test 2: Node.js project auto-detection"
DIR2="$FIXTURES_DIR/test2"
mkdir -p "$DIR2"
echo '{"name":"test"}' > "$DIR2/package.json"

RESULT=$(run_loader "$DIR2")
assert_eq "stack is nodejs" "$RESULT" "app.stack" "nodejs"
assert_eq "detectedStack is nodejs" "$RESULT" "context.detectedStack" "nodejs"
echo ""

# -----------------------------------------------------------
# Test 3: FastAPI + Next.js project (auto-detection)
# -----------------------------------------------------------
echo "Test 3: FastAPI + Next.js auto-detection"
DIR3="$FIXTURES_DIR/test3"
mkdir -p "$DIR3"
echo '{"name":"test"}' > "$DIR3/package.json"
echo 'module.exports = {}' > "$DIR3/next.config.js"
echo 'fastapi' > "$DIR3/requirements.txt"

RESULT=$(run_loader "$DIR3")
assert_eq "stack is fastapi-nextjs" "$RESULT" "app.stack" "fastapi-nextjs"
echo ""

# -----------------------------------------------------------
# Test 4: app-context.json from /make-it
# -----------------------------------------------------------
echo "Test 4: app-context.json from /make-it"
DIR4="$FIXTURES_DIR/test4"
mkdir -p "$DIR4/.make-it"
cat > "$DIR4/.make-it/app-context.json" << 'APPCTX'
{
  "project_name": "TaskHub",
  "project_slug": "task-hub",
  "stack": "fastapi-nextjs",
  "project_type": "web-app",
  "features": ["Task management", "Team dashboards", "Reporting"],
  "services": [
    {"name": "backend", "port": 8000, "health_check": "/health"},
    {"name": "frontend", "port": 3000, "health_check": "/"}
  ],
  "database": {"engine": "postgresql", "version": "16"},
  "auth": {"provider": "oidc"}
}
APPCTX

RESULT=$(run_loader "$DIR4")
assert_eq "app.name is TaskHub" "$RESULT" "app.name" "TaskHub"
assert_eq "app.slug is task-hub" "$RESULT" "app.slug" "task-hub"
assert_eq "app.stack is fastapi-nextjs" "$RESULT" "app.stack" "fastapi-nextjs"
assert_eq "app.database.engine is postgresql" "$RESULT" "app.database.engine" "postgresql"
assert_eq "app.auth.provider is oidc" "$RESULT" "app.auth.provider" "oidc"
assert_eq "context.hasMakeIt is true" "$RESULT" "context.hasMakeIt" "true"
echo ""

# -----------------------------------------------------------
# Test 5: .ship-it.yml overrides app-context.json
# -----------------------------------------------------------
echo "Test 5: .ship-it.yml overrides app-context.json"
DIR5="$FIXTURES_DIR/test5"
mkdir -p "$DIR5/.make-it"
cat > "$DIR5/.make-it/app-context.json" << 'APPCTX'
{
  "project_name": "TaskHub",
  "project_slug": "task-hub",
  "stack": "fastapi-nextjs"
}
APPCTX
cat > "$DIR5/.ship-it.yml" << 'SHIPIT'
app:
  name: "TaskHub Enterprise"
  slug: "task-hub"
  stack: "fastapi-nextjs"
SHIPIT

RESULT=$(run_loader "$DIR5")
assert_eq "name overridden to TaskHub Enterprise" "$RESULT" "app.name" "TaskHub Enterprise"
assert_eq "context.hasMakeIt is true" "$RESULT" "context.hasMakeIt" "true"
assert_eq "context.hasShipItYml is true" "$RESULT" "context.hasShipItYml" "true"
echo ""

# -----------------------------------------------------------
# Test 6: AWS infra configured
# -----------------------------------------------------------
echo "Test 6: AWS infrastructure configured"
DIR6="$FIXTURES_DIR/test6"
mkdir -p "$DIR6"
cat > "$DIR6/.ship-it.yml" << 'SHIPIT'
app:
  name: "TaskHub"
  slug: "task-hub"

infra:
  provider: aws
  aws:
    region: us-east-1
    account_id: "123456789012"
    ecr_registry: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
    ecs:
      cluster_name: "apps-cluster"
      execution_role_arn: "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"

deployment:
  environments:
    dev: dev
    production: production
  reviewers:
    - alice
    - bob
  strategy: rolling
SHIPIT

RESULT=$(run_loader "$DIR6")
assert_eq "infra.configured is true" "$RESULT" "infra.configured" "true"
assert_eq "infra.provider is aws" "$RESULT" "infra.provider" "aws"
echo ""

# -----------------------------------------------------------
# Test 7: AWS infra NOT configured (empty account_id)
# -----------------------------------------------------------
echo "Test 7: AWS infrastructure NOT configured"
DIR7="$FIXTURES_DIR/test7"
mkdir -p "$DIR7"
cat > "$DIR7/.ship-it.yml" << 'SHIPIT'
infra:
  provider: aws
  aws:
    region: us-east-1
    account_id: ""
SHIPIT

RESULT=$(run_loader "$DIR7")
assert_eq "infra.configured is false" "$RESULT" "infra.configured" "false"
echo ""

# -----------------------------------------------------------
# Test 8: .make-it-state.md with build-verify
# -----------------------------------------------------------
echo "Test 8: .make-it-state.md build-verified detection"
DIR8="$FIXTURES_DIR/test8"
mkdir -p "$DIR8"
cat > "$DIR8/.make-it-state.md" << 'STATE'
# Project State -- TaskHub
## Build-Verify Results
- Auth flow: PASSED
- API endpoints: 12 of 12 returning data
- Pages: 8 of 8 loading with content
STATE

RESULT=$(run_loader "$DIR8")
assert_eq "context.hasMakeItState is true" "$RESULT" "context.hasMakeItState" "true"
assert_eq "context.buildVerified is true" "$RESULT" "context.buildVerified" "true"
echo ""

# -----------------------------------------------------------
# Test 9: Full merge (all 3 sources)
# -----------------------------------------------------------
echo "Test 9: Full 3-source merge (ship-it.yml + app-context + auto-detect)"
DIR9="$FIXTURES_DIR/test9"
mkdir -p "$DIR9/.make-it"
echo '{"name":"test"}' > "$DIR9/package.json"
echo 'module.exports = {}' > "$DIR9/next.config.js"
echo 'fastapi' > "$DIR9/requirements.txt"
cat > "$DIR9/.make-it/app-context.json" << 'APPCTX'
{
  "project_name": "TaskHub",
  "project_slug": "task-hub",
  "stack": "fastapi-nextjs",
  "project_type": "web-app",
  "services": [
    {"name": "backend", "port": 8000, "health_check": "/health"},
    {"name": "frontend", "port": 3000, "health_check": "/"}
  ],
  "database": {"engine": "postgresql", "version": "16"},
  "auth": {"provider": "oidc"}
}
APPCTX
cat > "$DIR9/.ship-it.yml" << 'SHIPIT'
infra:
  provider: aws
  aws:
    region: us-east-1
    account_id: "123456789012"
    ecr_registry: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
    ecs:
      cluster_name: "apps-cluster"

deployment:
  reviewers:
    - devops-lead
  strategy: blue-green
SHIPIT

RESULT=$(run_loader "$DIR9")
assert_eq "app.name from app-context" "$RESULT" "app.name" "TaskHub"
assert_eq "infra.configured from ship-it.yml" "$RESULT" "infra.configured" "true"
assert_eq "strategy from ship-it.yml" "$RESULT" "deployment.strategy" "blue-green"
assert_eq "context.hasMakeIt true" "$RESULT" "context.hasMakeIt" "true"
assert_eq "context.hasShipItYml true" "$RESULT" "context.hasShipItYml" "true"
assert_eq "detectedStack is fastapi-nextjs" "$RESULT" "context.detectedStack" "fastapi-nextjs"
echo ""

# -----------------------------------------------------------
# Summary
# -----------------------------------------------------------
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed (of $TOTAL)"
echo "============================================"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "  All config loader tests passed."
    exit 0
else
    echo ""
    echo "  Some tests failed. Review output above."
    exit 1
fi
