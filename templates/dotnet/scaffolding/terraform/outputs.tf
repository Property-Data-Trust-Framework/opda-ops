output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role — managed in terraform/iam/"
  value       = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-github-actions"
}

output "api_gateway_invoke_url" {
  description = "Private API Gateway invoke URL (reachable only via the mTLS proxy)"
  value       = module.api_gateway.invoke_url
}
