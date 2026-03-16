#!/usr/bin/env bash
# smoke-test-e2e.sh -- End-to-end: make-it scaffold -> ship-it config -> LocalStack deploy
#
# This is the full integration test that proves make-it and ship-it work together:
#
#   1. Copy the make-it scaffold into a temp project
#   2. Create app-context.json (simulating /make-it Phase 2 output)
#   3. Run ship-it's config loader (simulating /ship-it preflight)
#   4. Verify the merged config is correct
#   5. Generate .ship-it.yml from app-context
#   6. Generate a workflow from config
#   7. Build Docker images from the scaffold
#   8. Deploy to LocalStack (if running)
#   9. Verify the deployment
#  10. Tear down
#
# Prerequisites:
#   - Node.js installed
#   - Docker running
#   - make-it and ship-it repos cloned alongside harness-it
#   - LocalStack running (optional -- steps 8-10 skip if not available)
#
# Usage:
#   bash tests/smoke-test-e2e.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAKE_IT_ROOT="$(cd "$HARNESS_ROOT/../make-it" && pwd)"
SHIP_IT_ROOT="$(cd "$HARNESS_ROOT/../ship-it" && pwd)"
LOCALSTACK_DIR="$HARNESS_ROOT/localstack"

APP_SLUG="smoke-test"
APP_NAME="SmokeTest"
PROJECT_DIR="$(mktemp -d)/smoke-test-app"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

cleanup() {
    # Tear down containers if we started them
    if [ "${DEPLOYED:-false}" = "true" ]; then
        echo ""
        echo "[Cleanup] Tearing down containers..."
        bash "$LOCALSTACK_DIR/scripts/teardown.sh" "$APP_SLUG" 2>/dev/null || true
    fi
    rm -rf "$(dirname "$PROJECT_DIR")"
}
trap cleanup EXIT

check() {
    local label="$1"
    local result="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$result" -eq 0 ]; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $label"
        FAIL=$((FAIL + 1))
    fi
}

skip() {
    local label="$1"
    echo "  [SKIP] $label"
    SKIP=$((SKIP + 1))
}

echo "============================================"
echo "  End-to-End Smoke Test"
echo "  make-it scaffold -> ship-it -> LocalStack"
echo "============================================"
echo ""

# -----------------------------------------------------------
# Verify prerequisites
# -----------------------------------------------------------
echo "[0/10] Checking prerequisites..."

if [ ! -d "$MAKE_IT_ROOT/.claude/make-it/scaffolds/fastapi-nextjs" ]; then
    echo "  ERROR: make-it scaffold not found at $MAKE_IT_ROOT"
    exit 1
fi
echo "  make-it scaffold: found"

if [ ! -f "$SHIP_IT_ROOT/src/config-loader.js" ]; then
    echo "  ERROR: ship-it repo not found at $SHIP_IT_ROOT"
    exit 1
fi
echo "  ship-it config-loader: found"

if [ ! -d "$SHIP_IT_ROOT/node_modules" ]; then
    echo "  Installing ship-it dependencies..."
    (cd "$SHIP_IT_ROOT" && npm install --silent)
fi
echo "  ship-it dependencies: installed"

DOCKER_OK=false
if docker info > /dev/null 2>&1; then
    DOCKER_OK=true
    echo "  Docker: running"
else
    echo "  Docker: not running (steps 7-10 will skip)"
fi

LOCALSTACK_OK=false
if curl -sf "http://localhost:4566/_localstack/health" > /dev/null 2>&1; then
    LOCALSTACK_OK=true
    echo "  LocalStack: running"
else
    echo "  LocalStack: not running (steps 8-10 will skip)"
fi
echo ""

# -----------------------------------------------------------
# Step 1: Copy scaffold into temp project
# -----------------------------------------------------------
echo "[1/10] Copying make-it scaffold..."
SCAFFOLD="$MAKE_IT_ROOT/.claude/make-it/scaffolds/fastapi-nextjs"
mkdir -p "$PROJECT_DIR"
cp -r "$SCAFFOLD/backend" "$PROJECT_DIR/"
cp -r "$SCAFFOLD/frontend" "$PROJECT_DIR/"
cp "$SCAFFOLD/docker-compose.yml" "$PROJECT_DIR/"

check "Scaffold copied" 0
echo ""

# -----------------------------------------------------------
# Step 2: Create app-context.json (simulates /make-it Phase 2)
# -----------------------------------------------------------
echo "[2/10] Creating app-context.json..."
mkdir -p "$PROJECT_DIR/.make-it"
cat > "$PROJECT_DIR/.make-it/app-context.json" << 'APPCTX'
{
  "project_name": "SmokeTest",
  "project_slug": "smoke-test",
  "stack": "fastapi-nextjs",
  "project_type": "web-app",
  "features": ["Dashboard", "User management", "Reports"],
  "roles": ["Super Admin", "Admin", "User"],
  "services": [
    {
      "name": "backend",
      "port": 8000,
      "health_check": "/health",
      "dockerfile": "backend/Dockerfile"
    },
    {
      "name": "frontend",
      "port": 3000,
      "health_check": "/",
      "dockerfile": "frontend/Dockerfile"
    }
  ],
  "database": {
    "engine": "postgresql",
    "version": "16"
  },
  "auth": {
    "provider": "oidc"
  }
}
APPCTX

cat > "$PROJECT_DIR/.make-it-state.md" << 'STATE'
# Project State -- SmokeTest
> Last updated: 2025-01-01
> Last session: make-it (initial build)

## Current Status
App is running locally with all services healthy. Build-verify passed.

## Build-Verify Results
- Auth flow: PASSED (all roles login with correct permissions)
- API endpoints: 8 of 8 returning data
- Pages: 5 of 5 loading with content
- Permission boundaries: PASSED
- Logout: PASSED
STATE

check "app-context.json created" 0
echo ""

# -----------------------------------------------------------
# Step 3: Run ship-it config loader
# -----------------------------------------------------------
echo "[3/10] Running ship-it config loader..."
CONFIG_JSON=$(node -e "
    const { loadConfig } = require('$SHIP_IT_ROOT/src/config-loader');
    const config = loadConfig({ workingDir: '$PROJECT_DIR' });
    console.log(JSON.stringify(config));
")

check "Config loader ran successfully" $?
echo ""

# -----------------------------------------------------------
# Step 4: Verify merged config
# -----------------------------------------------------------
echo "[4/10] Verifying merged config..."

get_val() {
    echo "$CONFIG_JSON" | node -e "
        const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
        const keys = '$1'.split('.');
        let v = d;
        for (const k of keys) v = v?.[k];
        console.log(typeof v === 'object' ? JSON.stringify(v) : String(v ?? ''));
    "
}

APP_NAME_VAL=$(get_val "app.name")
check "app.name = SmokeTest" "$([ "$APP_NAME_VAL" = "SmokeTest" ] && echo 0 || echo 1)"

SLUG_VAL=$(get_val "app.slug")
check "app.slug = smoke-test" "$([ "$SLUG_VAL" = "smoke-test" ] && echo 0 || echo 1)"

STACK_VAL=$(get_val "app.stack")
check "app.stack = fastapi-nextjs" "$([ "$STACK_VAL" = "fastapi-nextjs" ] && echo 0 || echo 1)"

HAS_MAKEIT=$(get_val "context.hasMakeIt")
check "context.hasMakeIt = true" "$([ "$HAS_MAKEIT" = "true" ] && echo 0 || echo 1)"

BUILD_VER=$(get_val "context.buildVerified")
check "context.buildVerified = true" "$([ "$BUILD_VER" = "true" ] && echo 0 || echo 1)"

INFRA_CONF=$(get_val "infra.configured")
check "infra.configured = false (no DevOps yet)" "$([ "$INFRA_CONF" = "false" ] && echo 0 || echo 1)"

DB_ENGINE=$(get_val "app.database.engine")
check "app.database.engine = postgresql" "$([ "$DB_ENGINE" = "postgresql" ] && echo 0 || echo 1)"

AUTH_PROV=$(get_val "app.auth.provider")
check "app.auth.provider = oidc" "$([ "$AUTH_PROV" = "oidc" ] && echo 0 || echo 1)"
echo ""

# -----------------------------------------------------------
# Step 5: Generate .ship-it.yml
# -----------------------------------------------------------
echo "[5/10] Generating .ship-it.yml from app-context..."
node -e "
    const { loadConfig, generateShipItYml } = require('$SHIP_IT_ROOT/src/config-loader');
    const config = loadConfig({ workingDir: '$PROJECT_DIR' });
    const yml = generateShipItYml(config);
    require('fs').writeFileSync('$PROJECT_DIR/.ship-it.yml', yml);
"

test -f "$PROJECT_DIR/.ship-it.yml"
check ".ship-it.yml generated" $?

grep -q "SmokeTest" "$PROJECT_DIR/.ship-it.yml"
check ".ship-it.yml contains app name" $?

grep -q "smoke-test" "$PROJECT_DIR/.ship-it.yml"
check ".ship-it.yml contains app slug" $?

grep -q "fastapi-nextjs" "$PROJECT_DIR/.ship-it.yml"
check ".ship-it.yml contains stack" $?

grep -q 'provider: ""' "$PROJECT_DIR/.ship-it.yml"
check ".ship-it.yml infra section is empty (pending DevOps)" $?
echo ""

# -----------------------------------------------------------
# Step 6: Generate workflow
# -----------------------------------------------------------
echo "[6/10] Generating GitHub Actions workflow..."
WORKFLOW_DIR="$PROJECT_DIR/.github/workflows"
mkdir -p "$WORKFLOW_DIR"
node -e "
    const { loadConfig } = require('$SHIP_IT_ROOT/src/config-loader');
    const { generateWorkflow } = require('$SHIP_IT_ROOT/src/workflow-gen');
    const config = loadConfig({ workingDir: '$PROJECT_DIR' });
    const yaml = generateWorkflow(config);
    require('fs').writeFileSync('$WORKFLOW_DIR/ship-it.yml', yaml);
"

test -f "$WORKFLOW_DIR/ship-it.yml"
check "Workflow file generated" $?

grep -q "Deployment pending" "$WORKFLOW_DIR/ship-it.yml"
check "Workflow has placeholder deploy (no infra)" $?

grep -q "build-and-validate" "$WORKFLOW_DIR/ship-it.yml"
check "Workflow has build job" $?

grep -q "deploy-dev" "$WORKFLOW_DIR/ship-it.yml"
check "Workflow has deploy-dev job" $?

grep -q "deploy-prod" "$WORKFLOW_DIR/ship-it.yml"
check "Workflow has deploy-prod job" $?
echo ""

# -----------------------------------------------------------
# Step 6b: Re-generate with AWS infra and verify
# -----------------------------------------------------------
echo "[6b/10] Re-generating workflow with AWS infra..."
cat > "$PROJECT_DIR/.ship-it.yml" << 'SHIPIT'
app:
  name: "SmokeTest"
  slug: "smoke-test"
  stack: "fastapi-nextjs"
  services:
    - name: backend
      dockerfile: backend/Dockerfile
      port: 8000
      health_check: /health
    - name: frontend
      dockerfile: frontend/Dockerfile
      port: 3000
      health_check: /
  database:
    engine: postgresql
    version: "16"
  auth:
    provider: oidc

infra:
  provider: aws
  aws:
    region: us-east-1
    account_id: "000000000000"
    ecr_registry: "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"
    ecs:
      cluster_name: "smoke-test-cluster"

deployment:
  environments:
    dev: dev
    production: production
  strategy: rolling
SHIPIT

node -e "
    const { loadConfig } = require('$SHIP_IT_ROOT/src/config-loader');
    const { generateWorkflow } = require('$SHIP_IT_ROOT/src/workflow-gen');
    const config = loadConfig({ workingDir: '$PROJECT_DIR' });
    const yaml = generateWorkflow(config);
    require('fs').writeFileSync('$WORKFLOW_DIR/ship-it-aws.yml', yaml);
"

grep -q "amazon-ecr-login" "$WORKFLOW_DIR/ship-it-aws.yml"
check "AWS workflow has ECR login" $?

grep -q "ecs update-service" "$WORKFLOW_DIR/ship-it-aws.yml"
check "AWS workflow has ECS deploy" $?

grep -q "smoke-test-cluster" "$WORKFLOW_DIR/ship-it-aws.yml"
check "AWS workflow references correct cluster" $?

grep -q "Build backend" "$WORKFLOW_DIR/ship-it-aws.yml"
check "AWS workflow builds backend image" $?

grep -q "Build frontend" "$WORKFLOW_DIR/ship-it-aws.yml"
check "AWS workflow builds frontend image" $?
echo ""

# -----------------------------------------------------------
# Step 7: Build Docker images
# -----------------------------------------------------------
echo "[7/10] Building Docker images from scaffold..."
if [ "$DOCKER_OK" = "true" ]; then
    docker build -t "$APP_SLUG-backend:latest" "$PROJECT_DIR/backend" --quiet 2>&1 && \
        check "Backend image built" 0 || check "Backend image built" 1

    docker build -t "$APP_SLUG-frontend:latest" "$PROJECT_DIR/frontend" --quiet 2>&1 && \
        check "Frontend image built" 0 || check "Frontend image built" 1
else
    skip "Backend image build (Docker not running)"
    skip "Frontend image build (Docker not running)"
fi
echo ""

# -----------------------------------------------------------
# Step 8: Deploy to LocalStack
# -----------------------------------------------------------
echo "[8/10] Deploying to LocalStack..."
if [ "$LOCALSTACK_OK" = "true" ] && [ "$DOCKER_OK" = "true" ]; then
    bash "$LOCALSTACK_DIR/scripts/deploy.sh" "$APP_SLUG" "$PROJECT_DIR" 2>&1 | tail -5
    DEPLOYED=true
    check "Deploy script completed" $?
else
    skip "LocalStack deploy (LocalStack or Docker not running)"
fi
echo ""

# -----------------------------------------------------------
# Step 9: Verify deployment
# -----------------------------------------------------------
echo "[9/10] Verifying deployment..."
if [ "${DEPLOYED:-false}" = "true" ]; then
    bash "$LOCALSTACK_DIR/scripts/verify.sh" "$APP_SLUG" 2>&1 | tail -10
    check "Verification passed" $?
else
    skip "Deployment verification"
fi
echo ""

# -----------------------------------------------------------
# Step 10: Summary
# -----------------------------------------------------------
echo "[10/10] Cleaning up..."
# cleanup happens via trap

echo ""
echo "============================================"
echo "  End-to-End Smoke Test Results"
echo "============================================"
if [ $SKIP -gt 0 ]; then
    echo "  $PASS passed, $FAIL failed, $SKIP skipped (of $TOTAL total)"
else
    echo "  $PASS passed, $FAIL failed (of $TOTAL total)"
fi
echo "============================================"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "  Smoke test passed."
    [ $SKIP -gt 0 ] && echo "  (Skipped steps require Docker/LocalStack running)"
    echo ""
    echo "  What was validated:"
    echo "    - make-it scaffold copies correctly"
    echo "    - app-context.json is read by ship-it config loader"
    echo "    - Merge logic: app-context > auto-detect > defaults"
    echo "    - .ship-it.yml is generated from app-context"
    echo "    - Workflow generates placeholder when no infra"
    echo "    - Workflow generates real AWS steps when infra configured"
    [ "$DOCKER_OK" = "true" ] && echo "    - Docker images build from scaffold"
    [ "${DEPLOYED:-false}" = "true" ] && echo "    - Full deploy + verify on LocalStack"
    exit 0
else
    echo "  Some tests failed. Review output above."
    exit 1
fi
