#!/usr/bin/env bash
# init-aws.sh -- Bootstrap AWS resources in LocalStack
#
# Creates the foundational infrastructure that every /make-it app needs.
# Run once after `docker compose up -d`. Idempotent -- safe to re-run.
#
# Uses `awslocal` inside the LocalStack container (no host AWS CLI needed).
#
# Usage:
#   bash bootstrap/init-aws.sh

set -euo pipefail

CONTAINER="localstack-localstack-1"
AWSLOCAL="docker exec $CONTAINER awslocal"

echo "Bootstrapping LocalStack AWS environment..."
echo ""

# Wait for LocalStack to be ready
echo "  Waiting for LocalStack..."
until curl -sf "http://localhost:4566/_localstack/health" > /dev/null 2>&1; do
    sleep 2
done
echo "  LocalStack is ready."

# S3: Terraform state bucket
echo "  Creating S3 bucket for Terraform state..."
$AWSLOCAL s3 mb s3://make-it-terraform-state 2>/dev/null || true

# IAM: ECS task execution role
echo "  Creating ECS task execution role..."
$AWSLOCAL iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ecs-tasks.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' 2>/dev/null || true

$AWSLOCAL iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
    2>/dev/null || true

# CloudWatch: Log group for all apps
echo "  Creating CloudWatch log group..."
$AWSLOCAL logs create-log-group --log-group-name /make-it/apps 2>/dev/null || true

# Verify resources were created
echo ""
echo "  Verifying..."
S3_CHECK=$($AWSLOCAL s3 ls 2>/dev/null | grep -c "make-it-terraform-state" || true)
IAM_CHECK=$($AWSLOCAL iam list-roles --query 'Roles[].RoleName' --output text 2>/dev/null | grep -c "ecsTaskExecutionRole" || true)
LOG_CHECK=$($AWSLOCAL logs describe-log-groups --query 'logGroups[].logGroupName' --output text 2>/dev/null | grep -c "/make-it/apps" || true)

if [ "$S3_CHECK" -ge 1 ] && [ "$IAM_CHECK" -ge 1 ] && [ "$LOG_CHECK" -ge 1 ]; then
    echo "  All resources verified."
else
    echo "  WARNING: Some resources may not have been created."
    echo "    S3 bucket: $([ "$S3_CHECK" -ge 1 ] && echo 'OK' || echo 'MISSING')"
    echo "    IAM role:  $([ "$IAM_CHECK" -ge 1 ] && echo 'OK' || echo 'MISSING')"
    echo "    Log group: $([ "$LOG_CHECK" -ge 1 ] && echo 'OK' || echo 'MISSING')"
fi

echo ""
echo "Bootstrap complete. Ready to deploy apps."
echo ""
echo "  Terraform state: s3://make-it-terraform-state"
echo "  Log group:       /make-it/apps"
echo "  ECS role:        ecsTaskExecutionRole"
echo ""
echo "Next: bash scripts/deploy.sh <app-slug> <project-dir>"
