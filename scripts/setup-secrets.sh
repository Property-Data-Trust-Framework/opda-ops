#!/usr/bin/env bash
# setup-secrets.sh — Push cert-based secrets to GitHub.
#
# Run this after bootstrap-api.sh and normalise-certs.sh, once you have your
# Raidiam certs in keys/ and your provider OAuth client ID to hand.
#
# The client ID here is the PROVIDER (server) identity used by the authorizer
# Lambda to introspect tokens with Raidiam. The CONSUMER (client) identity used
# by Bruno to obtain tokens is set separately by prepare-bruno-env.sh.
#
# USAGE
#   ./opda-ops/scripts/setup-secrets.sh <repo-name> <provider-client-id> [<provenance-kid>]
#
#   repo-name and provider-client-id are required. repo-name is the short name
#   (e.g. opda-uprn-validator), not the full org/repo path.
#
#   provenance-kid is optional — the KID issued by the Raidiam portal for the
#   provenance signing cert (keys/server/provenance/dataprov.key).
#   If omitted you will be prompted. Pass an empty string "" to skip.
#
# PREREQUISITES
#   - gh CLI installed and authenticated
#   - Certs normalised via normalise-certs.sh (canonical names must exist)
#   - Run from the sandbox root (the parent directory that contains opda-ops/)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG="OpenPropertyDataAssociation"
ENV_NAME="dev"

# ── Args ──────────────────────────────────────────────────────────────────────

REPO_NAME="${1:-}"
CLIENT_ID="${2:-}"
PROVENANCE_KID="${3-__unset__}"   # distinguish "not passed" from "passed empty"

if [[ -z "$REPO_NAME" ]]; then
  read -rp "Repo name (e.g. opda-uprn-validator): " REPO_NAME
fi
if [[ -z "$CLIENT_ID" ]]; then
  read -rp "OAuth client ID (provider/server): " CLIENT_ID
fi
if [[ "$PROVENANCE_KID" == "__unset__" ]]; then
  read -rp "Provenance signing KID (from Raidiam portal, leave blank to skip): " PROVENANCE_KID
fi
if [[ -z "$REPO_NAME" || -z "$CLIENT_ID" ]]; then
  echo "ERROR: repo name and client ID are both required." >&2
  exit 1
fi

FULL_REPO="${ORG}/${REPO_NAME}"
REPO_DIR="$(pwd)/${REPO_NAME}"
KEYS_DIR="$REPO_DIR/keys"

echo ""
echo "=== OPDA secrets setup ==="
echo "    Repo:      $FULL_REPO"
echo "    Keys from: $KEYS_DIR"
echo ""

# ── Validate cert files exist ─────────────────────────────────────────────────

check_file() {
  local path="$1" label="$2"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: $label not found at $path" >&2
    echo "       Run normalise-certs.sh first." >&2
    exit 1
  fi
}

check_file "$KEYS_DIR/server/transport/transport.crt"  "TRANSPORT_CERTIFICATE"
check_file "$KEYS_DIR/server/transport/transport.key"  "TRANSPORT_KEY"
check_file "$KEYS_DIR/server/signing/signing.key"      "SIGNING_KEY"
check_file "$KEYS_DIR/server/provenance/dataprov.key"  "DATAPROV_KEY"

# ── Push secrets to GitHub ────────────────────────────────────────────────────

echo ">>> Pushing secrets to GitHub..."

set_secret() {
  local name="$1" value="$2"
  gh secret set "$name" --body "$value" --env "$ENV_NAME" --repo "$FULL_REPO"
  echo "    secret: $name = (set)"
}

set_secret TRANSPORT_CERTIFICATE "$(cat "$KEYS_DIR/server/transport/transport.crt")"
set_secret TRANSPORT_KEY         "$(cat "$KEYS_DIR/server/transport/transport.key")"
set_secret SIGNING_KEY           "$(cat "$KEYS_DIR/server/signing/signing.key")"
set_secret DATAPROV_KEY          "$(cat "$KEYS_DIR/server/provenance/dataprov.key")"
set_secret OAUTH_CLIENT_ID       "$CLIENT_ID"

# ── Server TLS cert (public CA, e.g. Let's Encrypt) — opt-in ─────────────────
# Only set when keys/server/tls/tls.crt exists. Used by APIs with a custom
# domain where the proxy server cert must be from a publicly-trusted CA rather
# than the Raidiam transport cert.
if [[ -f "$KEYS_DIR/server/tls/tls.crt" && -f "$KEYS_DIR/server/tls/tls.key" ]]; then
  set_secret SERVER_TLS_CERTIFICATE "$(cat "$KEYS_DIR/server/tls/tls.crt")"
  set_secret SERVER_TLS_KEY         "$(cat "$KEYS_DIR/server/tls/tls.key")"
  echo "    (server TLS cert set from keys/server/tls/)"
fi

if [[ -n "$PROVENANCE_KID" ]]; then
  gh variable set PROVENANCE_SIGNING_KID --body "$PROVENANCE_KID" --env "$ENV_NAME" --repo "$FULL_REPO"
  echo "    variable: PROVENANCE_SIGNING_KID = $PROVENANCE_KID"
else
  echo "    variable: PROVENANCE_SIGNING_KID = (skipped — set manually in GitHub Actions environment)"
fi

echo ""
echo "=== Done. ==="
echo ""
echo "Next steps:"
echo "  1. Push to main — the pipeline will deploy the infrastructure."
echo "  2. Once the pipeline succeeds, run prepare-bruno-env.sh to generate scripts/bruno.env:"
echo "       cd $REPO_DIR && ./scripts/prepare-bruno-env.sh"
echo "     Share scripts/bruno.env with developers who can then run apply-bruno-env.sh."
