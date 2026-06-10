# `bucket` and `region` are supplied at init time.
#
# Local init:
#   BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text)"
#   terraform init \
#     -backend-config="bucket=$BUCKET" \
#     -backend-config="region=eu-west-2"
terraform {
  backend "s3" {
    key          = "dns/terraform.tfstate"
    use_lockfile = true
  }
}
