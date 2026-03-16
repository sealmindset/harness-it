# LocalStack Deployment Environment

Proves the full /ship-it deployment pipeline works end-to-end in isolation. No real AWS credentials needed.

## What This Validates

| Step | What | How |
|------|------|-----|
| 1 | Docker images build | `docker build` backend + frontend |
| 2 | Images push to registry | ECR in LocalStack |
| 3 | Infrastructure provisions | Terraform plan + apply against LocalStack |
| 4 | Secrets are stored | Secrets Manager in LocalStack |
| 5 | Database migrations run | Alembic against real PostgreSQL |
| 6 | App starts and is healthy | Health check endpoints |
| 7 | Frontend serves pages | HTTP 200/302 |
| 8 | Everything tears down cleanly | Remove all resources |

## Quick Start

```bash
cd ship-it/localstack

# Start LocalStack + PostgreSQL
docker compose up -d

# Bootstrap shared AWS resources (S3 state bucket, IAM role, log group)
bash bootstrap/init-aws.sh

# Deploy an app
bash scripts/deploy.sh task-hub ~/Documents/GitHub/task-hub

# Verify everything works
bash scripts/verify.sh task-hub

# Tear down the app (keeps LocalStack running)
bash scripts/teardown.sh task-hub

# Stop everything
docker compose down -v
```

## Terraform

The `terraform/` directory contains the same resource definitions that /make-it generates for production, configured to target LocalStack.

```bash
cd terraform
terraform init
terraform plan -var="app_slug=my-app"
terraform apply -var="app_slug=my-app"
```

To switch from LocalStack to real AWS: remove the `endpoints` block and `skip_*` flags from `providers.tf` and update `backend.tf` to point to a real S3 bucket.

## GitHub Actions

`.github/workflows/deploy-localstack.yml` runs the full pipeline in CI:
- Triggers on PRs touching `ship-it/**` or scaffold files
- Can also be run manually via `workflow_dispatch`
- No AWS credentials needed -- everything uses LocalStack

## Architecture

```
                    LocalStack (:4566)
                    ┌─────────────────────────────┐
                    │  ECR (image registry)        │
                    │  ECS (task definitions)      │
                    │  S3 (terraform state)        │
                    │  Secrets Manager (app secrets)│
                    │  CloudWatch (logs)           │
                    │  IAM (execution roles)       │
                    └─────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
   │ Backend │          │Frontend │          │PostgreSQL│
   │ :8000   │          │ :3000   │          │ :5432    │
   └─────────┘          └─────────┘          └──────────┘
   Docker container     Docker container     Docker container
   (simulates Fargate)  (simulates Fargate)  (simulates RDS)
```

PostgreSQL runs as a real container because LocalStack Community doesn't support RDS database instances. The app connects via `DATABASE_URL` -- same connection string format, only the hostname changes between local and production.

## Files

```
ship-it/localstack/
├── docker-compose.yml              # LocalStack + PostgreSQL
├── bootstrap/
│   └── init-aws.sh                 # One-time AWS resource setup
├── scripts/
│   ├── deploy.sh                   # Deploy an app
│   ├── verify.sh                   # Health check everything
│   └── teardown.sh                 # Clean up an app
├── terraform/
│   ├── providers.tf                # AWS provider → LocalStack
│   ├── main.tf                     # ECR, ECS, S3, Secrets, CloudWatch
│   ├── variables.tf                # Configurable values
│   └── outputs.tf                  # Resource URLs and ARNs
├── .github/workflows/
│   └── deploy-localstack.yml       # CI pipeline
└── README.md
```
