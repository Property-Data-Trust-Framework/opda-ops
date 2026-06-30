# Cheatsheet: Terraform

Paste-ready Terraform commands. Per-repo IAM lives in `terraform/iam/` with its own
state file ([[ADR-0010-github-oidc-aws-auth|ADR-0010]]); a `terraform destroy` on an
environment does **not** delete the GitHub Actions role.

## Recreate the per-repo GitHub Actions IAM role (when accidentally deleted)

```bash
# Init the iam/ root with the right state key
cd opda-lr-facade/terraform/iam && terraform init -backend-config="key=opda-lr-facade/iam/terraform.tfstate"

# Plan — should show only the github_actions role + its inline policy being created (+)
TF_VAR_name=opda-lr-facade TF_VAR_github_repo=Property-Data-Trust-Framework/opda-lr-facade terraform plan

# Apply (after reviewing the plan)
TF_VAR_name=opda-lr-facade TF_VAR_github_repo=Property-Data-Trust-Framework/opda-lr-facade terraform apply

# Verify the role exists post-apply
aws iam get-role --role-name opda-lr-facade-github-actions --query "Role.{Name:RoleName,Trust:AssumeRolePolicyDocument}" --output json
```
