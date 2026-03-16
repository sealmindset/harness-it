# harness-it

Test harness for developing and validating [/make-it](https://github.com/sealmindset/make-it) and [/ship-it](https://github.com/sealmindset/ship-it) — the two Claude Code skills that take vibe coders from app idea to production deployment.

## What This Is

`harness-it` is the integration test platform that proves make-it and ship-it work together seamlessly. It simulates the full AWS deployment environment locally using [LocalStack](https://localstack.cloud), so the entire pipeline can be validated in isolation — no real cloud credentials needed.

## Why It's Separate

| Repo | Audience | Purpose |
|------|----------|---------|
| [make-it](https://github.com/sealmindset/make-it) | Vibe coders | Build apps from plain English |
| [ship-it](https://github.com/sealmindset/ship-it) | Vibe coders + DevOps | Deploy apps to production |
| **harness-it** | Skill developers | Validate that make-it builds deploy correctly via ship-it |

Keeping the test harness separate prevents pollution and confusion. make-it and ship-it are clean, user-facing skills. harness-it is the backstage machinery that ensures they work.

## Quick Start

```bash
cd localstack

# Start the simulated AWS environment
docker compose up -d

# Bootstrap shared resources (S3 state bucket, IAM role, log groups)
bash bootstrap/init-aws.sh

# Deploy an app built by /make-it
bash scripts/deploy.sh my-app ~/Documents/GitHub/my-app

# Verify everything is healthy
bash scripts/verify.sh my-app

# Tear down when done
bash scripts/teardown.sh my-app
docker compose down -v
```

## What It Validates

| Layer | What's Tested | How |
|-------|---------------|-----|
| **Scaffold** | make-it's scaffold output builds as Docker images | `docker build` backend + frontend |
| **Registry** | Images push to a container registry | ECR in LocalStack |
| **Infrastructure** | Terraform provisions correctly | `terraform plan` + `apply` against LocalStack |
| **Secrets** | App secrets are stored and retrievable | Secrets Manager in LocalStack |
| **Database** | Migrations run successfully | Alembic against real PostgreSQL |
| **Runtime** | App starts and passes health checks | Backend `/health`, frontend HTTP 200 |
| **Pipeline** | Full deploy script runs end-to-end | 7-step `deploy.sh` |

## Structure

```
harness-it/
├── localstack/
│   ├── docker-compose.yml              # LocalStack + PostgreSQL
│   ├── bootstrap/
│   │   └── init-aws.sh                 # One-time AWS resource setup
│   ├── scripts/
│   │   ├── deploy.sh                   # Deploy a /make-it app (7 steps)
│   │   ├── verify.sh                   # Health check everything (9 checks)
│   │   └── teardown.sh                 # Clean up one app
│   ├── terraform/
│   │   ├── providers.tf                # AWS provider → LocalStack
│   │   ├── main.tf                     # ECR, ECS, S3, Secrets, CloudWatch
│   │   ├── variables.tf                # Configurable values
│   │   └── outputs.tf                  # Resource URLs and ARNs
│   ├── .github/workflows/
│   │   └── deploy-localstack.yml       # CI pipeline
│   └── README.md                       # LocalStack-specific docs
└── README.md                           # This file
```

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
   │ :8000   │          │ :3000   │          │ :5435    │
   └─────────┘          └─────────┘          └──────────┘
   (simulates ECS)      (simulates ECS)      (simulates RDS)
```

## Prerequisites

- Docker Desktop or Rancher Desktop
- Terraform (for infrastructure validation)
- A /make-it app to deploy (or use the scaffold smoke test)

No AWS CLI needed on the host — all AWS commands run via `awslocal` inside the LocalStack container.

## License

CC BY 4.0
