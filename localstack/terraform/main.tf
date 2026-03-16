# main.tf -- Infrastructure for a /make-it app
#
# This is the SAME structure that /make-it generates for production (Prompt #5).
# Against LocalStack, it validates that terraform plan/apply work correctly.
# Against real AWS, it creates actual resources.

locals {
  name_prefix = "${var.app_slug}-${var.environment}"
  tags = {
    App         = var.app_slug
    Environment = var.environment
    ManagedBy   = "terraform"
    CreatedBy   = "make-it"
  }
}

# -----------------------------------------------------------
# ECR Repositories
# -----------------------------------------------------------
resource "aws_ecr_repository" "backend" {
  name                 = "${local.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${local.name_prefix}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

# -----------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${local.name_prefix}/secrets"
  recovery_window_in_days = 0 # Immediate deletion for dev/test

  tags = local.tags
}

# -----------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/make-it/${local.name_prefix}/backend"
  retention_in_days = 30

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/make-it/${local.name_prefix}/frontend"
  retention_in_days = 30

  tags = local.tags
}

# -----------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

# -----------------------------------------------------------
# ECS Task Definitions
# -----------------------------------------------------------
resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = "arn:aws:iam::000000000000:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${aws_ecr_repository.backend.repository_url}:latest"
      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = local.tags
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = "arn:aws:iam::000000000000:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name  = "frontend"
      image = "${aws_ecr_repository.frontend.repository_url}:latest"
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "frontend"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "wget --spider -q http://127.0.0.1:3000 || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = local.tags
}

# -----------------------------------------------------------
# S3 Bucket (static assets, optional)
# -----------------------------------------------------------
resource "aws_s3_bucket" "assets" {
  bucket        = "${local.name_prefix}-assets"
  force_destroy = true

  tags = local.tags
}
