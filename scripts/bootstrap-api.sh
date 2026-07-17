#!/usr/bin/env bash
# bootstrap-api.sh — Create a new OPDA API repo from the dotnet template.
#
# Creates the GitHub repo, clones it locally, adds the shared submodule,
# copies in the scaffolding, installs and runs the dotnet new template, then
# creates the GitHub Actions environment and sets all resolvable variables.
#
# USAGE
#   ./opda-ops/scripts/bootstrap-api.sh [<repo-name>] [--skip-iam-bootstrap]
#
# If <repo-name> is omitted you will be prompted.
# The repo is created under the Property-Data-Trust-Framework GitHub org and fails fast if it exists.
# Use --skip-iam-bootstrap if you don't have local AWS credentials at bootstrap time.
#
# PREREQUISITES
#   - gh CLI installed and authenticated (gh auth login)
#   - aws CLI installed and configured
#   - dotnet 9 SDK installed
#   - terraform installed (optional — IAM bootstrap step skipped if not found)
#   - Run from the sandbox root (the parent directory that contains opda-ops/)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/templates/dotnet"
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
  read -rp "New repo name (e.g. opda-uprn-validator): " REPO_NAME
fi
if [[ -z "$REPO_NAME" ]]; then
  echo "ERROR: repo name is required." >&2
  exit 1
fi

FULL_REPO="${ORG}/${REPO_NAME}"
# Derive a default namespace by converting kebab-case to PascalCase.
DEFAULT_NAMESPACE="$(echo "$REPO_NAME" | awk -F'-' '{r=""; for(i=1;i<=NF;i++) r=r toupper(substr($i,1,1)) substr($i,2); print r}')"

read -rp "Base namespace [$DEFAULT_NAMESPACE]: " NAMESPACE
NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"

echo ""
echo "=== OPDA API bootstrap ==="
echo "    Repo:      $FULL_REPO"
echo "    Namespace: $NAMESPACE"
echo "    Environment:  $ENV_NAME"
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────

for tool in gh aws dotnet git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool is not installed or not in PATH." >&2
    exit 1
  fi
done

if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login" >&2
  exit 1
fi

# ── 1. Create the GitHub repo ─────────────────────────────────────────────────

echo ">>> [1/7] Creating repository $FULL_REPO..."
gh repo create "$FULL_REPO" --private
echo "    Created: https://github.com/$FULL_REPO"
echo ""

# ── 2. Clone locally ──────────────────────────────────────────────────────────

echo ">>> [2/7] Cloning repository..."
TARGET_DIR="$(pwd)/$REPO_NAME"
GH_TOKEN="$(gh auth token)"
git clone --quiet "https://x-access-token:${GH_TOKEN}@github.com/${FULL_REPO}.git" "$TARGET_DIR"
cd "$TARGET_DIR"
echo "    Cloned to: $TARGET_DIR"
echo ""

# ── 3. Add shared submodule ───────────────────────────────────────────────────

echo ">>> [3/7] Adding opda-shared-services submodule..."
git submodule add "https://github.com/Property-Data-Trust-Framework/opda-shared-services.git" opda-shared-services
echo ""

# ── 4. Copy scaffolding ───────────────────────────────────────────────────────

echo ">>> [4/7] Copying scaffolding..."
cp -r "$TEMPLATES_DIR/scaffolding/." .

sed -i.bak "s|\"name\": \"opda-api\"|\"name\": \"$REPO_NAME\"|" bruno/bruno.json
rm -f bruno/bruno.json.bak

# Write non-secret repo-specific values so future terraform apply runs in
# terraform/iam/ don't prompt for name/github_repo.
# The OIDC trust must match the sub claim GitHub actually SENDS. Newly-created
# repos get ID-pinned immutable subjects (org@id/repo@id) while older repos keep
# the legacy name form — always derive from the API rather than assuming.
SUB_REPO=$(gh api "repos/$FULL_REPO/actions/oidc/customization/sub" --jq '.sub_claim_prefix' 2>/dev/null | sed 's/^repo://')
[[ -z "$SUB_REPO" ]] && SUB_REPO="$FULL_REPO"
echo "    OIDC sub identity: $SUB_REPO"

cat > terraform/iam/terraform.tfvars <<TFVARS
# Non-secret values for this repo's IAM root. Committed intentionally —
# see .gitignore exception for terraform/iam/terraform.tfvars.
# github_repo holds the OIDC sub identity (may be the ID-pinned org@id/repo@id
# form on newer repos) — source: repos/<o>/<r>/actions/oidc/customization/sub.
name        = "$REPO_NAME"
github_repo = "$SUB_REPO"
TFVARS

echo "    Copied: .github/workflows/deploy.yml, terraform/, openapi/, bruno/"
echo "    Written: terraform/iam/terraform.tfvars (name, github_repo)"
echo "    Bruno collection name: $REPO_NAME"
echo ""

# ── 5. Generate .NET project from template ────────────────────────────────────

echo ">>> [5/7] Installing and running dotnet new template..."
dotnet new install "$TEMPLATES_DIR/template" --force >/dev/null
dotnet new opda-api -n "$NAMESPACE" --output .
echo "    Generated: src/$NAMESPACE/, tests/$NAMESPACE.Tests/, $NAMESPACE.sln, Dockerfile, docker-compose.yml"
echo ""
git add -A
git commit -m "Bootstrap: add scaffolding and $NAMESPACE API"
echo ""

# ── 6. Create GitHub Actions environment and set variables ────────────────────

echo ">>> [6/7] Creating GitHub Actions environment and setting variables..."

gh api --method PUT "repos/$FULL_REPO/environments/$ENV_NAME" --silent
echo "    Environment '$ENV_NAME' created."

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
    echo "    secret:   $name = (skipped — could not resolve)"
  fi
}

# CA trusted list — public, ships with the scaffolding
CA_PEM="$TEMPLATES_DIR/scaffolding/keys/ca/ca_trusted_list.pem"
if [[ -f "$CA_PEM" ]]; then
  set_secret CA_TRUSTED_LIST "$(cat "$CA_PEM")"
else
  echo "    secret:   CA_TRUSTED_LIST = (skipped — ca_trusted_list.pem not found in scaffolding)"
fi

# Resolve SHARED_SERVICES_ECR_BASE from AWS
ECR_BASE=$(aws ecr describe-repositories \
  --repository-names opda-shared-services \
  --query 'repositories[0].repositoryUri' --output text 2>/dev/null || true)
set_var SHARED_SERVICES_ECR_BASE "$ECR_BASE"

# Resolve latest image tags
AUTHORIZER_TAG=$(aws ecr describe-images \
  --repository-name opda-shared-services \
  --image-ids imageTag=authorizer-latest \
  --query 'imageDetails[0].imageTags' \
  --output json 2>/dev/null \
  | python3 -c "import sys,json; tags=json.loads(sys.stdin.read()); print(next((t[len('authorizer-'):] for t in tags if t.startswith('authorizer-') and t!='authorizer-latest'), ''), end='')" 2>/dev/null || true)
set_var AUTHORIZER_IMAGE_TAG "$AUTHORIZER_TAG"

set_var OAUTH_ISSUER "https://auth.directory.pdtf.raidiam.io"

set_var BYPASS_AUTH "false"
set_var EXTERNAL_DOMAIN_NAME ""

# Derive a sensible default proxy path prefix from the repo name.
# Pattern: opda-<middle>-api → /v1/<middle>  (e.g. opda-armalytix-api → /v1/armalytix)
PROXY_PREFIX="/v1/$(echo "$REPO_NAME" | sed 's/^opda-//' | sed 's/-api$//')"
set_var PROXY_PATH_PREFIX "$PROXY_PREFIX"

echo ""

# ── 7. IAM bootstrap ──────────────────────────────────────────────────────────

IAM_BOOTSTRAP_DONE=false

if [[ "$SKIP_IAM_BOOTSTRAP" == true ]]; then
  echo ">>> [7/7] IAM bootstrap skipped (--skip-iam-bootstrap)."
else
  echo ">>> [7/7] IAM bootstrap..."
  echo "    This creates the GitHub Actions IAM role so the pipeline can authenticate to AWS."
  echo "    It must run once before the first push and requires local AWS credentials."
  echo ""

  TF_DIR="$TARGET_DIR/terraform/iam"
  TF_BACKEND_KEY="$REPO_NAME/iam/terraform.tfstate"

  if ! command -v terraform &>/dev/null; then
    echo "    terraform not found — skipping. Run manually:"
    echo "      cd $TF_DIR"
    echo "      BUCKET=\"ops-terraform-state-\$(aws sts get-caller-identity --query Account --output text)\""
    echo "      terraform init -reconfigure -backend-config=\"bucket=\$BUCKET\" -backend-config=\"region=eu-west-2\" -backend-config=\"key=$TF_BACKEND_KEY\""
    echo "      TF_VAR_name=$REPO_NAME TF_VAR_github_repo=$FULL_REPO terraform apply"
  else
    cd "$TF_DIR"
    BUCKET="ops-terraform-state-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
    terraform init -reconfigure \
      -backend-config="bucket=$BUCKET" \
      -backend-config="region=eu-west-2" \
      -backend-config="key=$TF_BACKEND_KEY" \
      -input=false -no-color >/dev/null

    TF_VAR_name="$REPO_NAME" \
    TF_VAR_github_repo="$SUB_REPO" \
    terraform apply -auto-approve -input=false -no-color

    ROLE_ARN=$(TF_VAR_name="$REPO_NAME" \
      TF_VAR_github_repo="$SUB_REPO" \
      terraform output -raw github_actions_role_arn 2>/dev/null || true)

    cd "$TARGET_DIR"

    if [[ -n "$ROLE_ARN" ]]; then
      set_secret AWS_ROLE_ARN "$ROLE_ARN"
      IAM_BOOTSTRAP_DONE=true
      echo "    AWS_ROLE_ARN set: $ROLE_ARN"
    else
      echo "    Could not read role ARN from Terraform output — add AWS_ROLE_ARN manually."
    fi
  fi
fi

echo ""

# ── Done — print manual steps checklist ──────────────────────────────────────

echo "============================================================"
echo "  Bootstrap complete: $TARGET_DIR"
echo "============================================================"
echo ""
echo "Remaining steps before pushing to main:"
echo ""
echo "  1. Download your Raidiam certs and drop them into the correct subfolders:"
echo "       keys/server/transport/  ← server transport cert + key"
echo "       keys/server/signing/    ← server signing key (rtssigning — private_key_jwt AuthN)"
echo "       keys/server/provenance/ ← provenance signing cert + key (dataprov — response payload signing)"
echo "       keys/client/transport/  ← client transport cert + key (for Bruno)"
echo "       keys/client/signing/    ← client signing key (for Bruno Get Token)"
echo "       NOTE: provenance is a separate cert from signing — generate it separately in the Raidiam portal."
echo "             The portal-issued KID for the provenance cert is the PROVENANCE_SIGNING_KID GitHub variable."
echo ""
echo "  2. Normalise the GUID-named cert files to canonical names:"
echo "       ./$REPO_NAME/scripts/normalise-certs.sh"
echo ""
echo "  3. Push secrets to GitHub:"
echo "       ./opda-ops/scripts/setup-secrets.sh $REPO_NAME <provider-client-id>"
echo ""
if [[ "$IAM_BOOTSTRAP_DONE" == false ]]; then
  echo "  4. IAM bootstrap did not complete — run before pushing (derives repo/bucket/key itself):"
  echo "       ./$REPO_NAME/scripts/update-iam.sh"
  echo "     Then set the role secret from the freshly-applied role:"
  echo "       gh secret set AWS_ROLE_ARN --env $ENV_NAME --repo $FULL_REPO --body \"\$(aws iam get-role --role-name $REPO_NAME-github-actions --query Role.Arn --output text)\""
  echo ""
  echo "  5. Push to main — the pipeline will deploy the infrastructure."
  echo ""
  echo "  6. After the first successful deploy, prepare the Bruno env:"
  echo "       ./$REPO_NAME/scripts/prepare-bruno-env.sh --client-id <your-client-id>"
  echo "     This writes scripts/bruno.env for the shared proxy endpoint."
  echo "     Share scripts/bruno.env with developers who can then run:"
  echo "       ./scripts/apply-bruno-env.sh"
  echo ""
  echo "  7. In Bruno:"
  echo "       - Enable developer mode: Preferences → General → Enable Developer Mode"
  echo "       - Select the 'aws' environment"
  echo "       - Set the signingKey secret = contents of keys/client/signing/signing.key"
  echo "         (Bruno secret variables are not persisted — re-enter this each session)"
  echo "       - Run Get Token, then make API calls"
else
  echo "  4. Push to main — the pipeline will deploy the infrastructure."
  echo ""
  echo "  5. After the first successful deploy, run prepare-bruno-env.sh from the repo root:"
  echo "       cd $TARGET_DIR && ./scripts/prepare-bruno-env.sh --client-id <your-client-id>"
  echo "     This writes scripts/bruno.env for the shared proxy endpoint."
  echo "     Share scripts/bruno.env with developers who can then run:"
  echo "       ./scripts/apply-bruno-env.sh"
  echo ""
  echo "  6. In Bruno:"
  echo "       - Enable developer mode: Preferences → General → Enable Developer Mode"
  echo "       - Select the 'aws' environment"
  echo "       - Set the signingKey secret = contents of keys/client/signing/signing.key"
  echo "         (Bruno secret variables are not persisted — re-enter this each session)"
  echo "       - Run Get Token, then make API calls"
fi
echo "  After deploy is verified with Bruno — add the API to the docs site:"
echo "       1. Add an entry to opda-ops/api-docs/src/App.tsx (url, title, slug)"
echo "       2. Run ./deploy-api-docs.sh from the sandbox root"
echo "       See opda-ops/api-docs/README.md for details."
echo ""
echo "  Optional: set EXTERNAL_DOMAIN_NAME + EXTERNAL_HOSTED_ZONE_ID vars for DNS"
echo "  Optional: set BYPASS_AUTH=true if Raidiam certs are not yet available"
echo "============================================================"
