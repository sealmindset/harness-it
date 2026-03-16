output "ecr_backend_url" {
  description = "ECR repository URL for backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "secrets_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "backend_log_group" {
  description = "CloudWatch log group for backend"
  value       = aws_cloudwatch_log_group.backend.name
}

output "frontend_log_group" {
  description = "CloudWatch log group for frontend"
  value       = aws_cloudwatch_log_group.frontend.name
}

output "assets_bucket" {
  description = "S3 bucket for static assets"
  value       = aws_s3_bucket.assets.id
}
