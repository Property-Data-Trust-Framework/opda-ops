#!/usr/bin/env bash
# bootstrap-demo-bff.sh — One-time bootstrap for the OPDA demo BFF / Smoove webhook receiver.
#
# This repo differs from the standard OPDA API template in two key ways:
#   - No shared mTLS proxy: the API is publicly accessible (SPA + Smoove call it directly)
#   - No VPC on the Lambda: outbound calls to OPDA APIs go over the public internet
#     using the client mTLS certs; no NAT gateway needed
#
# What this script does:
#   1. Creates the GitHub repo
#   2. Clones it and sets up the directory scaffold
#   3. Bootstraps the IAM role so GitHub Actions can authenticate to AWS
#   4. Creates the GitHub Actions environment and sets all resolvable variables
#
# USAGE
#   ./opda-ops/scripts/bootstrap-demo-bff.sh [<repo-name>] [--skip-iam-bootstrap]
#
# PREREQUISITES
#   - gh CLI installed and authenticated (gh auth login)
#   - aws CLI installed and configured
#   - terraform installed (needed for IAM bootstrap step)
#   - Run from the sandbox root (the directory that contains opda-ops/)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG="Property-Data-Trust-Framework"
ENV_NAME="dev"
SKIP_IAM_BOOTSTRAP=false
REPO_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-iam-bootstrap) SKIP_IAM_BOOTSTRAP=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  REPO_NAME="${REPO_NAME:-$1}"; shift ;;
  esac
done

# ── Argument / prompt ─────────────────────────────────────────────────────────

if [[ -z "$REPO_NAME" ]]; then
  read -rp "New repo name (e.g. opda-demo-bff): " REPO_NAME
fi
if [[ -z "$REPO_NAME" ]]; then
  echo "ERROR: repo name is required." >&2
  exit 1
fi

FULL_REPO="${ORG}/${REPO_NAME}"
TARGET_DIR="$(pwd)/$REPO_NAME"

echo ""
echo "=== OPDA Demo BFF bootstrap ==="
echo "    Repo:        $FULL_REPO"
echo "    Environment: $ENV_NAME"
echo "    Target:      $TARGET_DIR"
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────

for tool in gh aws git terraform; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool is not installed or not in PATH." >&2
    exit 1
  fi
done

if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [[ -d "$TARGET_DIR" ]]; then
  echo "ERROR: $TARGET_DIR already exists." >&2
  exit 1
fi

# ── 1. Create the GitHub repo ─────────────────────────────────────────────────

echo ">>> [1/5] Creating repository $FULL_REPO..."
gh repo create "$FULL_REPO" --private
echo "    Created: https://github.com/$FULL_REPO"
echo ""

# ── 2. Clone and scaffold ─────────────────────────────────────────────────────

echo ">>> [2/5] Cloning and scaffolding..."
GH_TOKEN="$(gh auth token)"
git clone --quiet "https://x-access-token:${GH_TOKEN}@github.com/${FULL_REPO}.git" "$TARGET_DIR"
cd "$TARGET_DIR"

# Directory structure — no mTLS proxy module, no VPC, no submodule
mkdir -p \
  .github/workflows \
  src \
  spa \
  terraform/iam \
  keys/client/transport \
  keys/client/signing

# Placeholder README
cat > README.md << 'MD'
# OPDA Demo BFF

Backend-for-frontend Lambda + Smoove webhook receiver for the OPDA demo ecosystem.

- Public HTTP API Gateway (no shared mTLS proxy)
- VPC-less Lambda (outbound mTLS to OPDA APIs over public internet)
- CloudFront + S3 for the SPA frontend
MD

# IAM tfvars — committed intentionally (same pattern as other repos)
cat > terraform/iam/terraform.tfvars << TFVARS
# Non-secret values for this repo's IAM root.
name        = "$REPO_NAME"
github_repo = "$FULL_REPO"
TFVARS

# Copy the standard IAM Terraform from an existing repo as a starting point
IAM_SOURCE="$(pwd)/../opda-smoove-api/terraform/iam"
if [[ -d "$IAM_SOURCE" ]]; then
  cp "$IAM_SOURCE"/*.tf terraform/iam/
  cp "$IAM_SOURCE"/versions.tf terraform/iam/ 2>/dev/null || true
  echo "    Copied IAM Terraform from opda-smoove-api/terraform/iam"
else
  echo "    WARNING: could not find a reference IAM Terraform — add terraform/iam/*.tf manually."
fi

git add -A
git commit -m "Bootstrap: initial scaffold"
echo ""

# ── 3. IAM bootstrap ──────────────────────────────────────────────────────────

IAM_BOOTSTRAP_DONE=false
ROLE_ARN=""

if [[ "$SKIP_IAM_BOOTSTRAP" == true ]]; then
  echo ">>> [3/5] IAM bootstrap skipped (--skip-iam-bootstrap)."
else
  echo ">>> [3/5] IAM bootstrap (creates the GitHub Actions OIDC role)..."
  TF_DIR="$TARGET_DIR/terraform/iam"
  TF_BACKEND_KEY="$REPO_NAME/iam/terraform.tfstate"

  BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"

  cd "$TF_DIR"
  terraform init -reconfigure \
    -backend-config="bucket=$BUCKET" \
    -backend-config="region=eu-west-2" \
    -backend-config="key=$TF_BACKEND_KEY" \
    -input=false -no-color >/dev/null

  TF_VAR_name="$REPO_NAME" \
  TF_VAR_github_repo="$FULL_REPO" \
  terraform apply -auto-approve -input=false -no-color

  ROLE_ARN=$(TF_VAR_name="$REPO_NAME" \
    TF_VAR_github_repo="$FULL_REPO" \
    terraform output -raw github_actions_role_arn 2>/dev/null || true)
  cd "$TARGET_DIR"

  if [[ -n "$ROLE_ARN" ]]; then
    IAM_BOOTSTRAP_DONE=true
    echo "    IAM role created: $ROLE_ARN"
  else
    echo "    WARNING: could not read role ARN from Terraform output — set AWS_ROLE_ARN manually."
  fi
fi
echo ""

# ── 4. GitHub Actions environment ─────────────────────────────────────────────

echo ">>> [4/5] Creating GitHub Actions environment '$ENV_NAME'..."

gh api --method PUT "repos/$FULL_REPO/environments/$ENV_NAME" --silent
echo "    Environment '$ENV_NAME' created."
echo ""

set_var() {
  local name="$1" value="$2"
  if [[ -n "$value" ]]; then
    gh variable set "$name" --body "$value" --env "$ENV_NAME" --repo "$FULL_REPO"
    echo "    variable: $name = $value"
  else
    echo "    variable: $name = (skipped — could not resolve)"
  fi
}

set_secret() {
  local name="$1" value="$2"
  if [[ -n "$value" ]]; then
    gh secret set "$name" --body "$value" --env "$ENV_NAME" --repo "$FULL_REPO"
    echo "    secret:   $name = (set)"
  else
    echo "    secret:   $name = (skipped — value empty)"
  fi
}

echo ">>> [5/5] Setting variables and secrets..."

# IAM role (from bootstrap above, or skipped)
set_secret AWS_ROLE_ARN "$ROLE_ARN"

# OPDA shared proxy URL — the BFF calls OPDA APIs outbound via this hostname
OPDA_BASE_URL="https://dev.api.smartpropdata.org.uk"
set_var OPDA_API_BASE_URL "$OPDA_BASE_URL"

# Image tag placeholder — updated to real SHA on first deploy
set_var IMAGE_TAG "latest"

echo ""

# ── Done — print manual steps checklist ──────────────────────────────────────

echo "============================================================"
echo "  Bootstrap complete: $TARGET_DIR"
echo "============================================================"
echo ""
echo "Remaining steps before pushing to main:"
echo ""
echo "  1. Write the Terraform in terraform/ (not from the standard template):"
echo "       - ecr.tf         — ECR repository for the Lambda image"
echo "       - lambda.tf      — Lambda function, NO vpc_config block"
echo "       - api_gateway.tf — Public HTTP API v2 (NOT the shared-infra private REST API module)"
echo "       - ssm.tf         — SSM params for Smoove API key + OPDA client certs"
echo "       - iam.tf         — Lambda execution role, SSM read, no VPC policy"
echo "       - cloudfront.tf  — CloudFront distribution + S3 bucket for the SPA"
echo "       - variables.tf   — name, environment, image_tag, smoove_api_key, opda_client_cert/key"
echo "       - backend.tf     — same pattern as other repos (dynamic bucket via -backend-config)"
echo "       - locals.tf      — name_prefix"
echo "       - outputs.tf"
echo ""
echo "  2. Write the GitHub Actions deploy workflow in .github/workflows/deploy.yml."
echo "     Key differences from the standard workflow:"
echo "       - No TF_VAR_transport_certificate / TF_VAR_transport_key / TF_VAR_ca_trusted_list"
echo "       - No TF_VAR_authorizer_image_tag / TF_VAR_shared_services_ecr_base"
echo "       - Add TF_VAR_smoove_api_key: \${{ secrets.SMOOVE_API_KEY }}"
echo "       - Add TF_VAR_opda_client_cert: \${{ secrets.OPDA_CLIENT_CERT }}"
echo "       - Add TF_VAR_opda_client_key: \${{ secrets.OPDA_CLIENT_KEY }}"
echo ""
echo "  3. Set the remaining GitHub secrets (can't be auto-resolved):"
echo "       gh secret set SMOOVE_API_KEY     --env dev --repo $FULL_REPO"
echo "       gh secret set OPDA_CLIENT_CERT   --env dev --repo $FULL_REPO  # contents of keys/client/transport/transport.crt"
echo "       gh secret set OPDA_CLIENT_KEY    --env dev --repo $FULL_REPO  # contents of keys/client/transport/transport.key"
if [[ "$IAM_BOOTSTRAP_DONE" == false ]]; then
  echo ""
  echo "  3a. IAM bootstrap did not complete — run manually before pushing:"
  echo "       cd $TARGET_DIR/terraform/iam"
  echo "       BUCKET=\"ops-terraform-state-\$(aws sts get-caller-identity --query Account --output text)\""
  echo "       terraform init -reconfigure -backend-config=\"bucket=\$BUCKET\" -backend-config=\"region=eu-west-2\" -backend-config=\"key=$REPO_NAME/iam/terraform.tfstate\""
  echo "       TF_VAR_name=$REPO_NAME TF_VAR_github_repo=$FULL_REPO terraform apply"
  echo "       # Set the output github_actions_role_arn as AWS_ROLE_ARN in GitHub secrets."
fi
echo ""
echo "  4. Copy client certs for making outbound mTLS calls to the OPDA APIs:"
echo "       keys/client/transport/transport.crt"
echo "       keys/client/transport/transport.key"
echo "     These are the same Raidiam-issued certs used by the other OPDA repos."
echo ""
echo "  5. Scaffold the .NET Lambda (src/) and SPA (spa/)."
echo ""
echo "  6. Push to main — CI will build the Lambda image, push to ECR, and apply Terraform."
echo ""
echo "  7. After the first deploy, configure the SPA baseUrl to point at the"
echo "     CloudFront distribution domain and redeploy."
echo "============================================================"
