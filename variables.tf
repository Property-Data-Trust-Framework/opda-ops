variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "eu-west-2"
}

variable "github_org" {
  type        = string
  description = "GitHub organisation or user that owns the repos (e.g. \"tris\"). Per-API repos will use a data lookup to reference the OIDC provider created here."
}
