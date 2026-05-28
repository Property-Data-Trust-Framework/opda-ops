#!/usr/bin/env bash
#
# Pulls each API's OpenAPI spec from its sibling repo into public/specs/.
# Run before `npm run build` whenever specs have changed.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPECS_DIR="$SCRIPT_DIR/public/specs"

mkdir -p "$SPECS_DIR"

# Optional per-API server-URL overrides for local-dev parity with the CI flow.
# CI pulls the live NLB DNS from terraform output and substitutes the placeholder
# in the spec before uploading. For local builds, set these env vars in
# scripts/server-urls.env (gitignored) — leave blank to keep the placeholder.
[[ -f "$SCRIPT_DIR/scripts/server-urls.env" ]] && source "$SCRIPT_DIR/scripts/server-urls.env"

copy_spec() {
  local src="$1"
  local dst="$2"
  local host_var="$3"        # name of the env var holding the live host (optional)
  local placeholder="${4:-}" # token in the source spec to replace (optional)

  if [[ ! -f "$src" ]]; then
    echo "  $(basename "$dst") — source not found at $src (skipping)"
    return
  fi

  local host_value="${!host_var:-}"
  if [[ -n "$host_value" && -n "$placeholder" ]]; then
    sed "s|${placeholder}|${host_value}|g" "$src" > "$dst"
    echo "✓ $(basename "$dst") (host: $host_value)"
  else
    cp "$src" "$dst"
    echo "✓ $(basename "$dst") (no host substitution)"
  fi
}

copy_spec "$SANDBOX_ROOT/opda-lr-facade/openapi/api.yml"      "$SPECS_DIR/opda-lr-facade.yaml"      OPDA_LR_FACADE_HOST      "matls-mockapi.directory.pdtf.raidiam.io"
copy_spec "$SANDBOX_ROOT/opda-uprn-validator/openapi/api.yml" "$SPECS_DIR/opda-uprn-validator.yaml" OPDA_UPRN_VALIDATOR_HOST ""
copy_spec "$SANDBOX_ROOT/opda-mra-api/openapi/api.yml"        "$SPECS_DIR/opda-mra-api.yaml"        OPDA_MRA_API_HOST        ""
copy_spec "$SANDBOX_ROOT/opda-os-api/openapi/api.yml"         "$SPECS_DIR/opda-os-api.yaml"         OPDA_OS_API_HOST         ""

echo ""
echo "Specs in $SPECS_DIR:"
ls -1 "$SPECS_DIR"
