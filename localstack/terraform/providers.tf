# providers.tf -- AWS provider targeting LocalStack
#
# In production, remove the `endpoints` block and `skip_*` flags.
# Everything else stays the same.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket                      = "make-it-terraform-state"
    key                         = "localstack-test/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://localhost:4566"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    force_path_style            = true
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ecr            = "http://localhost:4566"
    ecs            = "http://localhost:4566"
    s3             = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    cloudwatchlogs = "http://localhost:4566"
    iam            = "http://localhost:4566"
    sts            = "http://localhost:4566"
  }
}
