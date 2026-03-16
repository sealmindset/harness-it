#!/usr/bin/env bash
# teardown.sh -- Remove a deployed app from the LocalStack environment
#
# Stops containers, removes AWS resources, and cleans up the database.
# Does NOT stop LocalStack or PostgreSQL themselves.
# Uses `awslocal` inside the LocalStack container (no host AWS CLI needed).
#
# Usage:
#   bash scripts/teardown.sh <app-slug>

set -euo pipefail

APP_SLUG="${1:?Usage: teardown.sh <app-slug>}"

CONTAINER="localstack-localstack-1"
AWSLOCAL="docker exec $CONTAINER awslocal"

echo "Tearing down: $APP_SLUG"
echo ""

# Stop and remove app containers
echo "  Stopping containers..."
docker rm -f "${APP_SLUG}-backend-deploy" "${APP_SLUG}-frontend-deploy" 2>/dev/null || true

# Remove ECS resources
echo "  Removing ECS resources..."
$AWSLOCAL ecs delete-service --cluster "$APP_SLUG-cluster" --service "$APP_SLUG-backend-svc" --force > /dev/null 2>&1 || true
$AWSLOCAL ecs deregister-task-definition --task-definition "$APP_SLUG-backend:1" > /dev/null 2>&1 || true
$AWSLOCAL ecs delete-cluster --cluster "$APP_SLUG-cluster" > /dev/null 2>&1 || true

# Remove ECR repositories
echo "  Removing ECR repositories..."
$AWSLOCAL ecr delete-repository --repository-name "$APP_SLUG-backend" --force > /dev/null 2>&1 || true
$AWSLOCAL ecr delete-repository --repository-name "$APP_SLUG-frontend" --force > /dev/null 2>&1 || true

# Remove secrets
echo "  Removing secrets..."
$AWSLOCAL secretsmanager delete-secret --secret-id "$APP_SLUG/dev" --force-delete-without-recovery > /dev/null 2>&1 || true

# Drop database
echo "  Dropping database..."
docker exec localstack-postgres-1 psql -U deploy_test -c "DROP DATABASE IF EXISTS ${APP_SLUG//-/_}" > /dev/null 2>&1 || true

# Remove Docker images
echo "  Removing Docker images..."
docker rmi "$APP_SLUG-backend:latest" "$APP_SLUG-frontend:latest" 2>/dev/null || true

echo ""
echo "Teardown complete: $APP_SLUG"
echo ""
echo "LocalStack and PostgreSQL are still running."
echo "To stop everything: docker compose down -v"
