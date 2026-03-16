variable "app_slug" {
  description = "Kebab-case app identifier (e.g., task-hub)"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "backend_cpu" {
  description = "Backend task CPU units (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "backend_memory" {
  description = "Backend task memory in MB"
  type        = number
  default     = 1024
}

variable "frontend_cpu" {
  description = "Frontend task CPU units"
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Frontend task memory in MB"
  type        = number
  default     = 512
}

variable "db_password" {
  description = "Database password (from Secrets Manager in production)"
  type        = string
  sensitive   = true
  default     = "deploy_test_password"
}
