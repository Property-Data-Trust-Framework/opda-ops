#!/usr/bin/env bash
# setup-github-env.sh — Optionally create a GitHub repo, then create a GitHub
# Actions environment and populate all secrets and variables required by an
# OPDA API repo.
#
# The script is IDEMPOTENT — re-running it will update existing values.
#
# USAGE
#   # Configure an existing repo:
#   ./scripts/setup-github-env.sh --repo Property-Data-Trust-Framework/opda-lr-facade --env dev
#
#   # Create a new repo then configure it:
#   ./scripts/setup-github-env.sh --new-repo-name opda-companies-house --env dev
#
#   # Preview without making any changes:
#   ./scripts/setup-github-env.sh --new-repo-name opda-companies-house --env dev --dry-run
#
# REQUIRED ENV VARS
#   Read the companion .env.example file for the full list.
#   Secrets are prefixed GH_SECRET_, variables are prefixed GH_VAR_.
#   Source a populated .env.<environment> file before running:
#     source scripts/.env.dev && ./scripts/setup-github-env.sh ...
#
#   The following values are auto-resolved from AWS if not set in the env file:
#     GH_SECRET_AWS_ROLE_ARN         — from IAM (role name: <repo>-github-actions)
#     GH_SECRET_EXTERNAL_HOSTED_ZONE_ID — from Route53
#     GH_VAR_EXTERNAL_DOMAIN_NAME    — from Route53 (zone name)
#     GH_VAR_SHARED_SERVICES_ECR_BASE — from ECR repository URI
#     GH_VAR_AUTHORIZER_IMAGE_TAG    — from ECR (latest authorizer image SHA)
#     GH_VAR_MTLS_PROXY_IMAGE_TAG    — from ECR (latest mtls image SHA)
#
# PREREQUISITES
#   - gh CLI installed and authenticated (gh auth login)
#   - Token must have: repo, admin:org (for org repo creation), secrets, actions scopes
#   - aws CLI installed and configured (for auto-resolution)
#
set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

REPO=""
NEW_REPO_NAME=""
ORG="Property-Data-Trust-Framework"
ENV_NAME="dev"
DESCRIPTION=""
VISIBILITY="private"
DRY_RUN=false
SETUP_SUBMODULES=true

usage() {
  echo "Usage:" >&2
  echo "  $0 --repo OWNER/REPO       --env ENV [--no-submodules] [--dry-run]" >&2
  echo "  $0 --new-repo-name NAME    --env ENV [--org ORG] [--description TEXT] [--public] [--no-submodules] [--dry-run]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)            REPO="$2";           shift 2 ;;
    --new-repo-name)   NEW_REPO_NAME="$2";  shift 2 ;;
    --org)             ORG="$2";            shift 2 ;;
    --env)             ENV_NAME="$2";       shift 2 ;;
    --description)     DESCRIPTION="$2";    shift 2 ;;
    --public)          VISIBILITY="public";  shift ;;
    --no-submodules)   SETUP_SUBMODULES=false; shift ;;
    --dry-run)         DRY_RUN=true;         shift ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

# Exactly one of --repo or --new-repo-name must be given.
if [[ -n "$REPO" && -n "$NEW_REPO_NAME" ]]; then
  echo "ERROR: --repo and --new-repo-name are mutually exclusive." >&2
  usage
fi
if [[ -z "$REPO" && -z "$NEW_REPO_NAME" ]]; then
  echo "ERROR: one of --repo or --new-repo-name is required." >&2
  usage
fi

# Derive REPO from org + name when creating a new one.
if [[ -n "$NEW_REPO_NAME" ]]; then
  REPO="${ORG}/${NEW_REPO_NAME}"
fi

REPO_NAME="${REPO##*/}"   # e.g. "opda-lr-facade" from "Property-Data-Trust-Framework/opda-lr-facade"

# ── Schema — define what every OPDA API repo environment needs ────────────────
#
# Add entries here when the Terraform or workflow requires new secrets/variables.

# Secrets that must come from the env file (no AWS source of truth).
REQUIRED_SECRETS=(
  OAUTH_CLIENT_ID               # OAuth2 client ID
  TRANSPORT_CERTIFICATE         # mTLS proxy transport certificate (PEM)
  TRANSPORT_KEY                 # mTLS proxy transport private key (PEM)
  CA_TRUSTED_LIST               # Trusted CA bundle for mTLS client cert verification (PEM)
  SIGNING_KEY                   # PEM RS256 private key for private_key_jwt assertions
  DATAPROV_KEY                  # PEM RS256 private key for response provenance signing
)

# Variables that must come from the env file (no AWS source of truth).
REQUIRED_VARS=(
  OAUTH_ISSUER                  # OAuth2 issuer URL (no trailing slash)
  PROVENANCE_SIGNING_KID        # KID issued by Raidiam for the provenance signing cert
)

# Default values applied when the env file does not set them.
: "${GH_VAR_OAUTH_ISSUER:=https://auth.directory.pdtf.raidiam.io}"
# Post-Raidiam-shutoff bootstraps: set GH_VAR_OAUTH_ISSUER=https://dev.api.smartpropdata.org.uk/auth
# in the env file instead (see wiki Runbook § "Auth modes" + the stub-auth bootstrap note).

# Secrets auto-resolved from AWS; env file values take precedence if set.
AUTO_SECRETS=(
  AWS_ROLE_ARN                  # IAM role: <repo-name>-github-actions
  EXTERNAL_HOSTED_ZONE_ID       # Route53 public hosted zone ID
)

# Variables auto-resolved from AWS; env file values take precedence if set.
AUTO_VARS=(
  EXTERNAL_DOMAIN_NAME          # Route53 public hosted zone name
  SHARED_PROXY_HOST             # Full hostname of the shared mTLS proxy (used for API spec publish)
  SHARED_SERVICES_ECR_BASE      # ECR repository URI for opda-shared-services
  AUTHORIZER_IMAGE_TAG          # SHA of the latest authorizer image
  MTLS_PROXY_IMAGE_TAG          # SHA of the latest mTLS proxy image
)

# Submodules — "name|url" pairs added to each OPDA API repo.
# Add entries here when a new shared service needs to be vendored in.
SUBMODULES=(
  "opda-shared-services|https://github.com/Property-Data-Trust-Framework/opda-shared-services.git"
)

# ── Pre-flight checks ─────────────────────────────────────────────────────────

TOTAL_STEPS=3
[[ -n "$NEW_REPO_NAME" ]]         && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ "$SETUP_SUBMODULES" == true ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

echo "=== OPDA GitHub environment setup ==="
echo "    Repo:        $REPO"
echo "    Environment: $ENV_NAME"
echo "    Dry run:     $DRY_RUN"
[[ -n "$NEW_REPO_NAME" ]]         && echo "    Creating:    yes (${VISIBILITY})"
[[ "$SETUP_SUBMODULES" == true ]] && echo "    Submodules:  yes (${#SUBMODULES[@]})"
echo ""

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found. Install from https://cli.github.com" >&2
  exit 1
fi
if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI is not authenticated. Run: gh auth login" >&2
  exit 1
fi

# ── AWS auto-resolution ───────────────────────────────────────────────────────
# Attempts to resolve deployment-essential values from AWS for any that are not
# already set in the environment. Env file values always take precedence.

if command -v aws &>/dev/null; then
  echo "Resolving values from AWS..."

  # ── IAM role ARN ────────────────────────────────────────────────────────────
  if [[ -z "${GH_SECRET_AWS_ROLE_ARN:-}" ]]; then
    GH_SECRET_AWS_ROLE_ARN=$(aws iam get-role \
      --role-name "${REPO_NAME}-github-actions" \
      --query 'Role.Arn' --output text 2>/dev/null || true)
    [[ -n "${GH_SECRET_AWS_ROLE_ARN:-}" ]] \
      && echo "  AWS_ROLE_ARN             = $GH_SECRET_AWS_ROLE_ARN" \
      || echo "  AWS_ROLE_ARN             = (not found — set GH_SECRET_AWS_ROLE_ARN in .env file)"
  else
    echo "  AWS_ROLE_ARN             = (from env file)"
  fi

  # ── Route53 hosted zone ──────────────────────────────────────────────────────
  if [[ -z "${GH_SECRET_EXTERNAL_HOSTED_ZONE_ID:-}" || -z "${GH_VAR_EXTERNAL_DOMAIN_NAME:-}" ]]; then
    ZONES_JSON=$(aws route53 list-hosted-zones \
      --query 'HostedZones[?!Config.PrivateZone]' \
      --output json 2>/dev/null || echo "[]")
    ZONE_COUNT=$(python3 -c "import sys,json; print(len(json.loads(sys.argv[1])))" "$ZONES_JSON" 2>/dev/null || echo "0")

    if [[ "$ZONE_COUNT" -eq 1 ]]; then
      RESOLVED_ZONE_ID=$(python3 -c \
        "import sys,json; z=json.loads(sys.argv[1])[0]; print(z['Id'].split('/')[-1], end='')" \
        "$ZONES_JSON" 2>/dev/null || true)
      RESOLVED_DOMAIN=$(python3 -c \
        "import sys,json; z=json.loads(sys.argv[1])[0]; print(z['Name'].rstrip('.'), end='')" \
        "$ZONES_JSON" 2>/dev/null || true)
      GH_SECRET_EXTERNAL_HOSTED_ZONE_ID="${GH_SECRET_EXTERNAL_HOSTED_ZONE_ID:-${RESOLVED_ZONE_ID}}"
      GH_VAR_EXTERNAL_DOMAIN_NAME="${GH_VAR_EXTERNAL_DOMAIN_NAME:-${RESOLVED_DOMAIN}}"
    elif [[ -n "${GH_VAR_EXTERNAL_DOMAIN_NAME:-}" ]]; then
      # Multiple zones — filter by the provided domain name.
      SEARCH="${GH_VAR_EXTERNAL_DOMAIN_NAME}."
      RESOLVED_ZONE_ID=$(python3 -c \
        "import sys,json; zones=json.loads(sys.argv[1]); match=[z for z in zones if z['Name']==sys.argv[2]]; print(match[0]['Id'].split('/')[-1] if match else '', end='')" \
        "$ZONES_JSON" "$SEARCH" 2>/dev/null || true)
      GH_SECRET_EXTERNAL_HOSTED_ZONE_ID="${GH_SECRET_EXTERNAL_HOSTED_ZONE_ID:-${RESOLVED_ZONE_ID}}"
    else
      echo "  EXTERNAL_HOSTED_ZONE_ID  = (multiple zones found — set GH_VAR_EXTERNAL_DOMAIN_NAME to disambiguate)"
    fi

    [[ -n "${GH_SECRET_EXTERNAL_HOSTED_ZONE_ID:-}" ]] \
      && echo "  EXTERNAL_HOSTED_ZONE_ID  = $GH_SECRET_EXTERNAL_HOSTED_ZONE_ID" \
      || true
    [[ -n "${GH_VAR_EXTERNAL_DOMAIN_NAME:-}" ]] \
      && echo "  EXTERNAL_DOMAIN_NAME     = $GH_VAR_EXTERNAL_DOMAIN_NAME" \
      || true
  else
    echo "  EXTERNAL_HOSTED_ZONE_ID  = (from env file)"
    echo "  EXTERNAL_DOMAIN_NAME     = (from env file)"
  fi

  # ── Shared proxy host (derived from ENV_NAME + EXTERNAL_DOMAIN_NAME) ─────────
  if [[ -z "${GH_VAR_SHARED_PROXY_HOST:-}" ]]; then
    GH_VAR_SHARED_PROXY_HOST="${ENV_NAME}.${GH_VAR_EXTERNAL_DOMAIN_NAME:-api.smartpropdata.org.uk}"
    echo "  SHARED_PROXY_HOST        = $GH_VAR_SHARED_PROXY_HOST (derived)"
  else
    echo "  SHARED_PROXY_HOST        = (from env file)"
  fi

  # ── ECR repository URI ───────────────────────────────────────────────────────
  if [[ -z "${GH_VAR_SHARED_SERVICES_ECR_BASE:-}" ]]; then
    GH_VAR_SHARED_SERVICES_ECR_BASE=$(aws ecr describe-repositories \
      --repository-names opda-shared-services \
      --query 'repositories[0].repositoryUri' --output text 2>/dev/null || true)
    [[ -n "${GH_VAR_SHARED_SERVICES_ECR_BASE:-}" ]] \
      && echo "  SHARED_SERVICES_ECR_BASE = $GH_VAR_SHARED_SERVICES_ECR_BASE" \
      || echo "  SHARED_SERVICES_ECR_BASE = (not found — has opda-shared-services been bootstrapped?)"
  else
    echo "  SHARED_SERVICES_ECR_BASE = (from env file)"
  fi

  # ── ECR image tags ───────────────────────────────────────────────────────────
  if [[ -z "${GH_VAR_AUTHORIZER_IMAGE_TAG:-}" ]]; then
    TAGS_JSON=$(aws ecr describe-images \
      --repository-name opda-shared-services \
      --image-ids imageTag=authorizer-latest \
      --query 'imageDetails[0].imageTags' \
      --output json 2>/dev/null || echo "[]")
    GH_VAR_AUTHORIZER_IMAGE_TAG=$(python3 -c \
      "import sys,json; tags=json.loads(sys.argv[1]); print(next((t[len('authorizer-'):] for t in tags if t.startswith('authorizer-') and t!='authorizer-latest'), ''), end='')" \
      "$TAGS_JSON" 2>/dev/null || true)
    [[ -n "${GH_VAR_AUTHORIZER_IMAGE_TAG:-}" ]] \
      && echo "  AUTHORIZER_IMAGE_TAG     = $GH_VAR_AUTHORIZER_IMAGE_TAG" \
      || echo "  AUTHORIZER_IMAGE_TAG     = (not found — has the shared-services pipeline run?)"
  else
    echo "  AUTHORIZER_IMAGE_TAG     = (from env file)"
  fi

  if [[ -z "${GH_VAR_MTLS_PROXY_IMAGE_TAG:-}" ]]; then
    TAGS_JSON=$(aws ecr describe-images \
      --repository-name opda-shared-services \
      --image-ids imageTag=mtls-latest \
      --query 'imageDetails[0].imageTags' \
      --output json 2>/dev/null || echo "[]")
    GH_VAR_MTLS_PROXY_IMAGE_TAG=$(python3 -c \
      "import sys,json; tags=json.loads(sys.argv[1]); print(next((t[len('mtls-'):] for t in tags if t.startswith('mtls-') and t!='mtls-latest'), ''), end='')" \
      "$TAGS_JSON" 2>/dev/null || true)
    [[ -n "${GH_VAR_MTLS_PROXY_IMAGE_TAG:-}" ]] \
      && echo "  MTLS_PROXY_IMAGE_TAG     = $GH_VAR_MTLS_PROXY_IMAGE_TAG" \
      || echo "  MTLS_PROXY_IMAGE_TAG     = (not found — has the shared-services pipeline run?)"
  else
    echo "  MTLS_PROXY_IMAGE_TAG     = (from env file)"
  fi

  echo ""
else
  echo "Note: aws CLI not found — skipping auto-resolution. All values must be set in the env file."
  echo ""
fi

# ── Validation ────────────────────────────────────────────────────────────────
# Check that every value is present — either from the env file or auto-resolved.

MISSING=0

for name in "${REQUIRED_SECRETS[@]}"; do
  var="GH_SECRET_${name}"
  if [[ -z "${!var:-}" ]]; then
    echo "MISSING secret:   $var" >&2
    MISSING=$((MISSING + 1))
  fi
done

for name in "${REQUIRED_VARS[@]}"; do
  var="GH_VAR_${name}"
  if [[ -z "${!var:-}" ]]; then
    echo "MISSING variable: $var" >&2
    MISSING=$((MISSING + 1))
  fi
done

for name in "${AUTO_SECRETS[@]}"; do
  var="GH_SECRET_${name}"
  if [[ -z "${!var:-}" ]]; then
    echo "MISSING secret:   $var (not set in env file and could not be resolved from AWS)" >&2
    MISSING=$((MISSING + 1))
  fi
done

for name in "${AUTO_VARS[@]}"; do
  var="GH_VAR_${name}"
  if [[ -z "${!var:-}" ]]; then
    echo "MISSING variable: $var (not set in env file and could not be resolved from AWS)" >&2
    MISSING=$((MISSING + 1))
  fi
done

if [[ $MISSING -gt 0 ]]; then
  echo "" >&2
  echo "ERROR: $MISSING required value(s) missing. See scripts/.env.example." >&2
  exit 1
fi

echo "All required values present."
echo ""

# ── Helper functions ──────────────────────────────────────────────────────────

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

set_secret() {
  local name="$1"
  local value="$2"
  echo "  secret: $name"
  run gh secret set "$name" \
    --body "$value" \
    --env "$ENV_NAME" \
    --repo "$REPO"
}

set_variable() {
  local name="$1"
  local value="$2"
  echo "  variable: $name = $value"
  run gh variable set "$name" \
    --body "$value" \
    --env "$ENV_NAME" \
    --repo "$REPO"
}

# ── Step counter ──────────────────────────────────────────────────────────────

STEP=0
next_step() {
  STEP=$((STEP + 1))
  echo ">>> [$STEP/$TOTAL_STEPS] $1"
}

# ── 1. Create repo (if requested) ─────────────────────────────────────────────

if [[ -n "$NEW_REPO_NAME" ]]; then
  next_step "Creating repository '$REPO' (${VISIBILITY})..."

  if gh repo view "$REPO" &>/dev/null; then
    echo "  Repository already exists — skipping creation."
  else
    CREATE_ARGS=(
      "$REPO"
      "--${VISIBILITY}"
    )
    [[ -n "$DESCRIPTION" ]] && CREATE_ARGS+=(--description "$DESCRIPTION")

    run gh repo create "${CREATE_ARGS[@]}"
    echo "  Created: https://github.com/$REPO"
  fi
  echo ""
fi

# ── 2. Set up submodules (if enabled) ────────────────────────────────────────

if [[ "$SETUP_SUBMODULES" == true ]]; then
  next_step "Configuring submodules on $REPO..."

  if [[ "$DRY_RUN" == true ]]; then
    for entry in "${SUBMODULES[@]}"; do
      sub_name="${entry%%|*}"
      sub_url="${entry##*|}"
      echo "  [dry-run] git submodule add $sub_url $sub_name"
    done
  else
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    # Clone the repo (use GitHub CLI token so no interactive auth is needed).
    GH_TOKEN="$(gh auth token)"
    CLONE_URL="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
    git clone --quiet "$CLONE_URL" "$tmp_dir/repo"
    cd "$tmp_dir/repo"

    # git submodule add refuses to run without a user identity; set a transient one.
    git config user.email "setup-github-env@opda-ops"
    git config user.name  "OPDA setup script"

    ADDED=0
    for entry in "${SUBMODULES[@]}"; do
      sub_name="${entry%%|*}"
      sub_url="${entry##*|}"

      # Check .gitmodules for an existing entry with this path.
      if [[ -f .gitmodules ]] && grep -q "path = ${sub_name}" .gitmodules; then
        echo "  submodule '$sub_name' already registered — skipping."
      else
        echo "  adding submodule: $sub_name → $sub_url"
        git submodule add "$sub_url" "$sub_name"
        ADDED=$((ADDED + 1))
      fi
    done

    if [[ $ADDED -gt 0 ]]; then
      git commit -m "chore: add shared submodule(s) via setup-github-env.sh"
      git push origin HEAD
      echo "  Committed and pushed $ADDED new submodule(s)."
    else
      echo "  All submodules already present — nothing to commit."
    fi

    cd - >/dev/null
    # trap will clean up tmp_dir on EXIT
  fi
  echo ""
fi

# ── 3. Create / update the environment ───────────────────────────────────────

next_step "Creating environment '$ENV_NAME' on $REPO..."
run gh api \
  --method PUT \
  "repos/$REPO/environments/$ENV_NAME" \
  --silent
echo ""

# ── N. Set secrets ────────────────────────────────────────────────────────────

next_step "Setting secrets..."
for name in "${REQUIRED_SECRETS[@]}" "${AUTO_SECRETS[@]}"; do
  var="GH_SECRET_${name}"
  set_secret "$name" "${!var}"
done
echo ""

# ── N. Set variables ──────────────────────────────────────────────────────────

next_step "Setting variables..."
for name in "${REQUIRED_VARS[@]}" "${AUTO_VARS[@]}"; do
  var="GH_VAR_${name}"
  set_variable "$name" "${!var}"
done

echo ""
echo "=== Done. ==="
echo "    Repo:        https://github.com/$REPO"
echo "    Environment: https://github.com/$REPO/settings/environments"
