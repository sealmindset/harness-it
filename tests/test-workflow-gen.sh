#!/usr/bin/env bash
# test-workflow-gen.sh -- Validate ship-it workflow generator output
#
# Tests that the workflow generator produces correct YAML for:
#   - AWS with infra configured
#   - Azure with infra configured
#   - Pending (no infra)
#   - Reusable workflow reference
#
# Prerequisites:
#   - Node.js installed
#   - ship-it repo cloned alongside harness-it
#
# Usage:
#   bash tests/test-workflow-gen.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIP_IT_ROOT="$(cd "$HARNESS_ROOT/../ship-it" && pwd)"

if [ ! -f "$SHIP_IT_ROOT/src/workflow-gen.js" ]; then
    echo "ERROR: ship-it repo not found at $SHIP_IT_ROOT"
    exit 1
fi

if [ ! -d "$SHIP_IT_ROOT/node_modules" ]; then
    (cd "$SHIP_IT_ROOT" && npm install --silent)
fi

OUTPUT_DIR="$(mktemp -d)"
PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT

# Helper: generate a workflow from a config JSON
gen_workflow() {
    local config_json="$1"
    local output_file="$2"
    node -e "
        const { generateWorkflow } = require('$SHIP_IT_ROOT/src/workflow-gen');
        const config = $config_json;
        const yaml = generateWorkflow(config);
        require('fs').writeFileSync('$output_file', yaml);
    "
}

assert_contains() {
    local label="$1"
    local file="$2"
    local pattern="$3"
    TOTAL=$((TOTAL + 1))

    if grep -q "$pattern" "$file"; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $label"
        echo "         pattern not found: $pattern"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local label="$1"
    local file="$2"
    local pattern="$3"
    TOTAL=$((TOTAL + 1))

    if ! grep -q "$pattern" "$file"; then
        echo "  [PASS] $label"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $label"
        echo "         pattern should NOT be found: $pattern"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "  ship-it Workflow Generator Tests"
echo "============================================"
echo ""

# -----------------------------------------------------------
# Test 1: AWS workflow with infra configured
# -----------------------------------------------------------
echo "Test 1: AWS workflow with configured infra"
OUT1="$OUTPUT_DIR/aws-workflow.yml"
gen_workflow '{
  "app": {
    "name": "TaskHub",
    "slug": "task-hub",
    "services": [
      {"name": "backend", "dockerfile": "backend/Dockerfile", "port": 8000, "healthCheck": "/health"},
      {"name": "frontend", "dockerfile": "frontend/Dockerfile", "port": 3000, "healthCheck": "/"}
    ]
  },
  "infra": {
    "configured": true,
    "provider": "aws",
    "aws": {
      "region": "us-east-1",
      "account_id": "123456789012",
      "ecr_registry": "123456789012.dkr.ecr.us-east-1.amazonaws.com",
      "ecs": {"cluster_name": "apps-cluster"}
    }
  },
  "deployment": {
    "environments": {"dev": "dev", "production": "production"},
    "reusableWorkflow": null
  }
}' "$OUT1"

assert_contains "has AWS ECR login step" "$OUT1" "amazon-ecr-login"
assert_contains "has AWS configure-credentials" "$OUT1" "configure-aws-credentials"
assert_contains "builds backend image" "$OUT1" "Build backend"
assert_contains "builds frontend image" "$OUT1" "Build frontend"
assert_contains "deploys to ECS" "$OUT1" "ecs update-service"
assert_contains "references apps-cluster" "$OUT1" "apps-cluster"
assert_contains "has deploy-dev job" "$OUT1" "deploy-dev"
assert_contains "has deploy-prod job" "$OUT1" "deploy-prod"
assert_not_contains "no placeholder text" "$OUT1" "Deployment pending"
echo ""

# -----------------------------------------------------------
# Test 2: Azure workflow with infra configured
# -----------------------------------------------------------
echo "Test 2: Azure workflow with configured infra"
OUT2="$OUTPUT_DIR/azure-workflow.yml"
gen_workflow '{
  "app": {
    "name": "TaskHub",
    "slug": "task-hub",
    "services": [
      {"name": "backend", "dockerfile": "backend/Dockerfile", "port": 8000, "healthCheck": "/health"}
    ]
  },
  "infra": {
    "configured": true,
    "provider": "azure",
    "azure": {
      "acr_name": "myorgacr",
      "acr_login_server": "myorgacr.azurecr.io",
      "aks": {"cluster_name": "apps-aks", "resource_group": "rg-shared-aks"}
    }
  },
  "deployment": {
    "environments": {"dev": "dev", "production": "production"},
    "reusableWorkflow": null
  }
}' "$OUT2"

assert_contains "has Azure login step" "$OUT2" "azure/login"
assert_contains "has ACR login" "$OUT2" "az acr login"
assert_contains "builds backend image" "$OUT2" "Build backend"
assert_contains "deploys via kubectl" "$OUT2" "kubectl set image"
assert_contains "references AKS cluster" "$OUT2" "apps-aks"
assert_not_contains "no placeholder text" "$OUT2" "Deployment pending"
echo ""

# -----------------------------------------------------------
# Test 3: Pending workflow (no infra)
# -----------------------------------------------------------
echo "Test 3: Pending workflow (no infra configured)"
OUT3="$OUTPUT_DIR/pending-workflow.yml"
gen_workflow '{
  "app": {"name": "TaskHub", "slug": "task-hub", "services": []},
  "infra": {"configured": false, "provider": ""},
  "deployment": {
    "environments": {"dev": "dev", "production": "production"},
    "reusableWorkflow": null
  }
}' "$OUT3"

assert_contains "has placeholder text" "$OUT3" "Deployment pending"
assert_contains "mentions .ship-it.yml" "$OUT3" "ship-it.yml"
assert_contains "has build-and-validate job" "$OUT3" "build-and-validate"
assert_contains "has deploy-dev job" "$OUT3" "deploy-dev"
assert_not_contains "no ECR references" "$OUT3" "amazon-ecr-login"
assert_not_contains "no Azure references" "$OUT3" "azure/login"
echo ""

# -----------------------------------------------------------
# Test 4: Reusable workflow reference
# -----------------------------------------------------------
echo "Test 4: Reusable workflow caller"
OUT4="$OUTPUT_DIR/caller-workflow.yml"
gen_workflow '{
  "app": {"name": "TaskHub", "slug": "task-hub", "services": []},
  "infra": {"configured": false, "provider": ""},
  "deployment": {
    "environments": {"dev": "dev", "production": "production"},
    "reusableWorkflow": "myorg/shared-workflows/.github/workflows/ship-it-pipeline.yml@main"
  }
}' "$OUT4"

assert_contains "references reusable workflow" "$OUT4" "myorg/shared-workflows"
assert_contains "passes dev environment" "$OUT4" "environment-dev"
assert_contains "passes prod environment" "$OUT4" "environment-prod"
assert_contains "inherits secrets" "$OUT4" "secrets: inherit"
echo ""

# -----------------------------------------------------------
# Test 5: Valid YAML syntax (all outputs)
# -----------------------------------------------------------
echo "Test 5: Valid YAML syntax check"
for f in "$OUTPUT_DIR"/*.yml; do
    TOTAL=$((TOTAL + 1))
    fname=$(basename "$f")
    # Use node to parse YAML
    if node -e "require('$SHIP_IT_ROOT/node_modules/js-yaml').load(require('fs').readFileSync('$f','utf8'))" 2>/dev/null; then
        echo "  [PASS] $fname is valid YAML"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $fname is NOT valid YAML"
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# -----------------------------------------------------------
# Summary
# -----------------------------------------------------------
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed (of $TOTAL)"
echo "============================================"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "  All workflow generator tests passed."
    exit 0
else
    echo ""
    echo "  Some tests failed. Review output above."
    exit 1
fi
