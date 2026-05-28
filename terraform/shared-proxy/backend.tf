# `bucket`, `region`, and `key` are supplied at init time; `key` varies by environment.
#
# Local init:
#   BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
#   terraform init \
#     -backend-config="bucket=$BUCKET" \
#     -backend-config="region=eu-west-2" \
#     -backend-config="key=shared-proxy/${ENV}/terraform.tfstate"
terraform {
  backend "s3" {
    use_lockfile = true
  }
}
