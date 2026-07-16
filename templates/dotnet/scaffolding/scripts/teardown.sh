#!/usr/bin/env bash
# teardown.sh — Destroy all AWS infrastructure for this API.
#
# USAGE
#   ./scripts/teardown.sh [environment]
#
#   environment   Deployment environment to destroy (default: dev)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"
ENVIRONMENT="${1:-dev}"
GITHUB_ORG="Property-Data-Trust-Framework"

echo ""
echo "!!! WARNING !!!"
echo ""
echo "This will permanently destroy ALL AWS infrastructure for:"
echo "  Repository:  $REPO_NAME"
echo "  Environment: $ENVIRONMENT"
echo ""
echo "Resources destroyed: Lambda, ECS, NLB, API Gateway, VPC, ECR, IAM roles."
echo "This action CANNOT be undone."
echo ""
read -rp "Type 'yes' to continue: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "!!! FINAL WARNING !!!"
echo ""
read -rp "Type the repository name ($REPO_NAME) to confirm: " CONFIRM2
if [[ "$CONFIRM2" != "$REPO_NAME" ]]; then
  echo "Aborted — name did not match."
  exit 0
fi

echo ""
echo "=== Destroying $REPO_NAME ($ENVIRONMENT) ==="
echo ""

cd "$REPO_ROOT/terraform"

terraform init -backend-config="key=$REPO_NAME/$ENVIRONMENT/terraform.tfstate"

TF_VAR_name="$REPO_NAME" \
TF_VAR_environment="$ENVIRONMENT" \
TF_VAR_github_repo="$GITHUB_ORG/$REPO_NAME" \
terraform destroy

echo ""
echo "Environment resources destroyed."
echo ""
echo "NOTE: The GitHub Actions IAM role ($REPO_NAME-github-actions) is managed in"
echo "terraform/iam/ (separate state) and was NOT destroyed by this script."
echo "If you want to fully remove it (e.g. decommissioning the repo entirely), run:"
echo "  cd $REPO_ROOT/terraform/iam"
echo "  terraform init -backend-config=\"key=$REPO_NAME/iam/terraform.tfstate\""
echo "  terraform destroy"
echo ""
echo "After any destroy you will need to re-run the IAM bootstrap before the"
echo "pipeline can deploy again. See the README or bootstrap-api.sh for details."
