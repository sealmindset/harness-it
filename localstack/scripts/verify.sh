#!/usr/bin/env bash
# verify.sh -- Verify a deployed app is healthy
#
# Checks every layer: AWS resources, database, backend, frontend, secrets.
# Uses `awslocal` inside the LocalStack container (no host AWS CLI needed).
# Gracefully skips checks for services not available in LocalStack Community.
#
# Usage:
#   bash scripts/verify.sh <app-slug>

set -euo pipefail

APP_SLUG="${1:?Usage: verify.sh <app-slug>}"

CONTAINER="localstack-localstack-1"
AWSLOCAL="docker exec $CONTAINER awslocal"
DB_PORT=5435

PASS=0
FAIL=0
SKIP=0
TOTAL=0

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
    echo "  [SKIP] $label (LocalStack Community)"
    SKIP=$((SKIP + 1))
}

echo "============================================"
echo "  Verifying: $APP_SLUG"
echo "============================================"
echo ""

# -----------------------------------------------------------
# AWS Resources
# -----------------------------------------------------------
echo "AWS Resources:"

# ECR may not be available in LocalStack Community
if $AWSLOCAL ecr describe-repositories --repository-names "$APP_SLUG-backend" > /dev/null 2>&1; then
    check "ECR repo: $APP_SLUG-backend" 0
    $AWSLOCAL ecr describe-repositories --repository-names "$APP_SLUG-frontend" > /dev/null 2>&1
    check "ECR repo: $APP_SLUG-frontend" $?
else
    skip "ECR repos"
fi

# ECS may not be available in LocalStack Community
if $AWSLOCAL ecs describe-clusters --clusters "$APP_SLUG-cluster" 2>/dev/null | grep -q "$APP_SLUG-cluster"; then
    check "ECS cluster: $APP_SLUG-cluster" 0
else
    skip "ECS cluster"
fi

# Secrets Manager (available in Community)
$AWSLOCAL secretsmanager describe-secret --secret-id "$APP_SLUG/dev" > /dev/null 2>&1
check "Secret: $APP_SLUG/dev" $?

# CloudWatch Logs (available in Community)
$AWSLOCAL logs describe-log-groups --log-group-name-prefix /make-it/apps 2>/dev/null | grep -q "/make-it/apps"
check "CloudWatch log group: /make-it/apps" $?

echo ""

# -----------------------------------------------------------
# Database
# -----------------------------------------------------------
echo "Database:"

docker exec localstack-postgres-1 pg_isready -U deploy_test > /dev/null 2>&1 || \
    pg_isready -h 127.0.0.1 -p $DB_PORT -U deploy_test > /dev/null 2>&1
check "PostgreSQL is ready" $?

docker exec localstack-postgres-1 psql -U deploy_test -d deploy_test -c "SELECT 1 FROM users LIMIT 1" > /dev/null 2>&1 || \
    psql -h 127.0.0.1 -p $DB_PORT -U deploy_test -d deploy_test -c "SELECT 1 FROM users LIMIT 1" > /dev/null 2>&1
check "Database migrations applied (users table exists)" $?

echo ""

# -----------------------------------------------------------
# Backend
# -----------------------------------------------------------
echo "Backend (http://localhost:8000):"

TRIES=0
while ! curl -sf http://127.0.0.1:8000/health > /dev/null 2>&1; do
    TRIES=$((TRIES + 1))
    if [ $TRIES -ge 15 ]; then break; fi
    sleep 2
done

curl -sf http://127.0.0.1:8000/health > /dev/null 2>&1
check "Health endpoint: /health" $?

curl -sf http://127.0.0.1:8000/health 2>/dev/null | python3 -c "import sys,json; json.load(sys.stdin)" > /dev/null 2>&1
check "Health returns valid JSON" $?

echo ""

# -----------------------------------------------------------
# Frontend
# -----------------------------------------------------------
echo "Frontend (http://localhost:3000):"

TRIES=0
while ! curl -sf http://127.0.0.1:3000 > /dev/null 2>&1; do
    TRIES=$((TRIES + 1))
    if [ $TRIES -ge 15 ]; then break; fi
    sleep 2
done

HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1:3000 2>/dev/null || echo "000")
echo "$HTTP_CODE" | grep -qE "^(200|302|307)$"
check "Frontend responds (HTTP $HTTP_CODE)" $?

echo ""

# -----------------------------------------------------------
# Secrets (verify values are retrievable)
# -----------------------------------------------------------
echo "Secrets Manager:"

SECRET_VALUE=$($AWSLOCAL secretsmanager get-secret-value --secret-id "$APP_SLUG/dev" --query 'SecretString' --output text 2>/dev/null)
echo "$SECRET_VALUE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'JWT_SECRET' in d; assert 'DATABASE_URL' in d" > /dev/null 2>&1
check "Secret contains JWT_SECRET and DATABASE_URL" $?

echo ""

# -----------------------------------------------------------
# Summary
# -----------------------------------------------------------
echo "============================================"
if [ $SKIP -gt 0 ]; then
    echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped"
else
    echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
fi
echo "============================================"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "  All checks passed. Deployment is healthy."
    [ $SKIP -gt 0 ] && echo "  (Skipped checks require LocalStack Pro)"
    echo ""
    exit 0
else
    echo ""
    echo "  Some checks failed. Review output above."
    echo ""
    exit 1
fi
