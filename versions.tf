terraform {
  # This repo intentionally uses local state — it creates the remote state
  # backend used by all other repos, so it cannot use it itself.
  # Run `terraform init && terraform apply` once with admin credentials.

  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.26.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
