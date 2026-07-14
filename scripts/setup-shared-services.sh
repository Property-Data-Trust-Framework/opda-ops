#!/usr/bin/env bash
# setup-shared-services.sh — Configure the GitHub Actions environment for
# opda-shared-services so its publish pipeline can authenticate to AWS.
#
# Unlike the consumer API repos, opda-shared-services only needs a single
# secret (AWS_ROLE_ARN) — it pushes Docker images and manages ECR via
# Terraform, but has no per-API config.
#
# USAGE
#   export GH_SECRET_AWS_ROLE_ARN="arn:aws:iam::<account-id>:role/opda-shared-services-github-actions"
#   ./scripts/setup-shared-services.sh
#
#   # Preview without making any changes:
#   ./scripts/setup-shared-services.sh --dry-run
#
# PREREQUISITES
#   - gh CLI installed and authenticated (gh auth login)
#   - AWS IAM role for opda-shared-services GitHub Actions already created
#     (see opda-ops Terraform outputs or create manually with the OIDC trust
#     policy scoped to OpenPropertyDataAssociation/opda-shared-services)
#
set -euo pipefail

REPO="OpenPropertyDataAssociation/opda-shared-services"
ENV_NAME="dev"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "=== opda-shared-services GitHub environment setup ==="
echo "    Repo:        $REPO"
echo "    Environment: $ENV_NAME"
echo "    Dry run:     $DRY_RUN"
echo ""

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found." >&2; exit 1
fi
if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login" >&2; exit 1
fi

if [[ -z "${GH_SECRET_AWS_ROLE_ARN:-}" ]]; then
  echo "ERROR: GH_SECRET_AWS_ROLE_ARN is not set." >&2
  echo "  Export the ARN of the GitHub Actions IAM role for opda-shared-services:" >&2
  echo "  export GH_SECRET_AWS_ROLE_ARN=\"arn:aws:iam::<account-id>:role/opda-shared-services-github-actions\"" >&2
  exit 1
fi

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo ">>> [1/2] Creating environment '$ENV_NAME'..."
run gh api \
  --method PUT \
  "repos/$REPO/environments/$ENV_NAME" \
  --silent

echo ""
echo ">>> [2/2] Setting AWS_ROLE_ARN secret..."
run gh secret set AWS_ROLE_ARN \
  --body "$GH_SECRET_AWS_ROLE_ARN" \
  --env "$ENV_NAME" \
  --repo "$REPO"

echo ""
echo "=== Done. ==="
echo "    Environment: https://github.com/$REPO/settings/environments"
echo ""
echo "NOTE: After the first publish run, copy the ECR URL from the workflow"
echo "summary and set it as SHARED_SERVICES_ECR_BASE in each consumer repo:"
echo "  GH_VAR_SHARED_SERVICES_ECR_BASE=<url> ./scripts/setup-github-env.sh --repo OpenPropertyDataAssociation/<api-repo> --env dev"
