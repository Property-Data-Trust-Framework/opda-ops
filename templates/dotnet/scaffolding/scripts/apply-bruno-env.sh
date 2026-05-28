#!/usr/bin/env bash
# apply-bruno-env.sh — Configure local Bruno from scripts/bruno.env.
#
# Run this to configure your Bruno setup. You need scripts/bruno.env —
# either run prepare-bruno-env.sh yourself (requires AWS access) or get
# the file from a team member who has already run it.
#
# USAGE (from repo root)
#   ./scripts/apply-bruno-env.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRUNO_ENV_FILE="$SCRIPT_DIR/bruno.env"
BRUNO_BRU="$REPO_DIR/bruno/environments/aws.bru"
BRUNO_JSON="$REPO_DIR/bruno/bruno.json"

if [[ ! -f "$BRUNO_ENV_FILE" ]]; then
  echo "ERROR: $BRUNO_ENV_FILE not found." >&2
  echo "       Run prepare-bruno-env.sh (requires AWS access), or" >&2
  echo "       get scripts/bruno.env from a team member who has." >&2
  exit 1
fi

if [[ ! -f "$BRUNO_BRU" ]]; then
  echo "ERROR: Bruno environment file not found: $BRUNO_BRU" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$BRUNO_ENV_FILE"

if [[ -z "${CLIENT_ID:-}" ]]; then
  echo "ERROR: bruno.env is missing CLIENT_ID." >&2
  exit 1
fi

# Support both old (NLB_HOSTNAME only) and new (BASE_URL + CERT_DOMAIN) bruno.env formats.
BASE_URL="${BASE_URL:-https://${NLB_HOSTNAME:-}}"
CERT_DOMAIN="${CERT_DOMAIN:-${NLB_HOSTNAME:-}}"

if [[ -z "$BASE_URL" || -z "$CERT_DOMAIN" ]]; then
  echo "ERROR: bruno.env is missing BASE_URL (or NLB_HOSTNAME) — re-run prepare-bruno-env.sh." >&2
  exit 1
fi

echo ""
echo "=== Applying Bruno environment ==="
echo ""

sed -i.bak "s|baseUrl:.*|baseUrl: ${BASE_URL}|" "$BRUNO_BRU"
rm -f "${BRUNO_BRU}.bak"
echo "Updated: $BRUNO_BRU"
echo "    baseUrl  = $BASE_URL"

sed -i.bak "s|clientId:.*|clientId: ${CLIENT_ID}|" "$BRUNO_BRU"
rm -f "${BRUNO_BRU}.bak"
echo "    clientId = $CLIENT_ID"

if [[ -f "$BRUNO_JSON" ]]; then
  # Replace the API endpoint cert domain (any domain that is not a Raidiam directory domain).
  # Handles both Bruno formats: old (array) and new (object with nested "certs" array).
  python3 - "$BRUNO_JSON" "$CERT_DOMAIN" <<'PYEOF'
import json, sys
path, new_domain = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
certs_field = data.get("clientCertificates", [])
entries = certs_field.get("certs", []) if isinstance(certs_field, dict) else certs_field
for entry in entries:
    if "raidiam.io" not in entry.get("domain", ""):
        entry["domain"] = new_domain
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
  echo "Updated: $BRUNO_JSON"
  echo "    cert domain = $CERT_DOMAIN"
fi

echo ""
echo "Bruno files updated. To complete setup:"
echo "  1. Enable developer mode: Preferences → General → Enable Developer Mode"
echo "  2. Open the collection and select the 'aws' environment"
echo "  3. Set the signingKey secret = contents of keys/client/signing/signing.key"
echo "     (Bruno secret variables are not persisted — re-enter this each session)"
echo "  4. Run Get Token, then make API calls"
