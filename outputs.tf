output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state. Use in per-API backend configs."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "github_oidc_provider_arn" {
  description = "ARN of the shared GitHub Actions OIDC provider. Reference this in per-API IAM role trust policies via a data lookup."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "account_id" {
  description = "AWS account ID (for use in per-API backend configs)."
  value       = data.aws_caller_identity.current.account_id
}
