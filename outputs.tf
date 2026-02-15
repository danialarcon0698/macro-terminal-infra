# ============================================================
# Outputs — Important values shown after deploy
# ============================================================

# ---- URLs ----
output "api_url" {
  description = "Public API URL"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "frontend_url" {
  description = "Public frontend URL"
  value       = "https://${var.domain_name}"
}

output "api_gateway_url" {
  description = "API Gateway default URL (for debugging)"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

# ---- ECR ----
output "ecr_api_url" {
  description = "ECR repository URL for API"
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_data_provider_url" {
  description = "ECR repository URL for data provider"
  value       = aws_ecr_repository.data_provider.repository_url
}

# ---- S3 ----
output "frontend_bucket_name" {
  description = "S3 bucket name for frontend files"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.frontend.id
}

# ---- Database ----
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

# ---- Bastion ----
output "bastion_instance_id" {
  description = "Bastion EC2 instance ID (for SSM tunnel)"
  value       = aws_instance.bastion.id
}

# ---- ECS ----
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_api_service_name" {
  description = "ECS API service name"
  value       = aws_ecs_service.api.name
}

output "ecs_data_provider_service_name" {
  description = "ECS data provider service name"
  value       = aws_ecs_service.data_provider.name
}
