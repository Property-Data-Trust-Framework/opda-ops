#!/usr/bin/env bash
# normalise-certs.sh — Copy Raidiam-supplied cert files to canonical names.
#
# Drop the GUID-named files from the Raidiam portal into the correct subfolder
# under keys/, then run this script. It will copy them to the standard
# names expected by setup-github-env.sh and Bruno.
#
# Canonical names per folder:
#   keys/server/signing/    → signing.key, signing.pem
#   keys/server/transport/  → transport.key, transport.crt
#   keys/server/provenance/ → dataprov.key, dataprov.pem
#   keys/client/signing/    → signing.key, signing.pem
#   keys/client/transport/  → transport.key, transport.crt
#
# .csr files are ignored. The script aborts a folder if it finds more than one
# non-canonical .key or .pem file — drop only the files for that folder first.
#
# USAGE
#   ./scripts/normalise-certs.sh [--keys-dir <path>]
#
#   --keys-dir   Path to the keys directory (default: ./keys)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/keys"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keys-dir) KEYS_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$KEYS_DIR" ]]; then
  echo "ERROR: keys directory not found: $KEYS_DIR" >&2
  exit 1
fi

ERRORS=0
COPIES=0

# ── Folder definitions ────────────────────────────────────────────────────────
# Each entry: "relative/path|canonical-key-name|canonical-cert-name|cert-extension"

FOLDERS=(
  "server/signing|signing.key|signing.pem|pem"
  "server/transport|transport.key|transport.crt|pem"
  "server/provenance|dataprov.key|dataprov.pem|pem"
  "client/signing|signing.key|signing.pem|pem"
  "client/transport|transport.key|transport.crt|pem"
)

# ── Helper ────────────────────────────────────────────────────────────────────

process_folder() {
  local rel_path="$1"
  local canonical_key="$2"
  local canonical_cert="$3"
  local cert_ext="$4"
  local dir="$KEYS_DIR/$rel_path"

  echo "--- $rel_path"

  if [[ ! -d "$dir" ]]; then
    echo "    SKIP: folder does not exist"
    return
  fi

  # Find non-canonical .key files (exclude .csr and already-canonical names)
  key_files=()
  while IFS= read -r f; do key_files+=("$f"); done < <(find "$dir" -maxdepth 1 -name "*.key" \
    ! -name "$canonical_key" | sort)

  # Find non-canonical cert files (.pem or .crt, exclude canonical names)
  cert_files=()
  while IFS= read -r f; do cert_files+=("$f"); done < <(find "$dir" -maxdepth 1 \( -name "*.pem" -o -name "*.crt" \) \
    ! -name "$canonical_cert" | sort)

  local has_canonical_key=false
  local has_canonical_cert=false
  [[ -f "$dir/$canonical_key" ]] && has_canonical_key=true
  [[ -f "$dir/$canonical_cert" ]] && has_canonical_cert=true

  # ── Key ───────────────────────────────────────────────────────────────────

  if [[ ${#key_files[@]} -eq 0 ]]; then
    if [[ "$has_canonical_key" == true ]]; then
      echo "    $canonical_key — already present, skipping"
    else
      echo "    $canonical_key — no source file found (drop the .key file from the portal here)"
    fi
  elif [[ ${#key_files[@]} -gt 1 ]]; then
    echo "    ERROR: multiple non-canonical .key files found — remove all but one:" >&2
    for f in "${key_files[@]}"; do echo "      $(basename "$f")" >&2; done
    ERRORS=$((ERRORS + 1))
  else
    local src_key="${key_files[0]}"
    if [[ "$has_canonical_key" == true ]]; then
      echo "    $canonical_key — already present, skipping (source: $(basename "$src_key"))"
    else
      cp "$src_key" "$dir/$canonical_key"
      echo "    $canonical_key — copied from $(basename "$src_key")"
      COPIES=$((COPIES + 1))
    fi
  fi

  # ── Cert ──────────────────────────────────────────────────────────────────

  if [[ ${#cert_files[@]} -eq 0 ]]; then
    if [[ "$has_canonical_cert" == true ]]; then
      echo "    $canonical_cert — already present, skipping"
    else
      echo "    $canonical_cert — no source file found (drop the .pem file from the portal here)"
    fi
  elif [[ ${#cert_files[@]} -gt 1 ]]; then
    echo "    ERROR: multiple non-canonical .pem/.crt files found — remove all but one:" >&2
    for f in "${cert_files[@]}"; do echo "      $(basename "$f")" >&2; done
    ERRORS=$((ERRORS + 1))
  else
    local src_cert="${cert_files[0]}"
    if [[ "$has_canonical_cert" == true ]]; then
      echo "    $canonical_cert — already present, skipping (source: $(basename "$src_cert"))"
    else
      cp "$src_cert" "$dir/$canonical_cert"
      echo "    $canonical_cert — copied from $(basename "$src_cert")"
      COPIES=$((COPIES + 1))
    fi
  fi
}

# ── Run ───────────────────────────────────────────────────────────────────────

echo "=== Normalising Raidiam certs in: $KEYS_DIR"
echo ""

for entry in "${FOLDERS[@]}"; do
  IFS='|' read -r rel_path canonical_key canonical_cert cert_ext <<< "$entry"
  process_folder "$rel_path" "$canonical_key" "$canonical_cert" "$cert_ext"
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────

if [[ $ERRORS -gt 0 ]]; then
  echo "ERROR: $ERRORS folder(s) had ambiguous files — resolve them and re-run." >&2
  exit 1
fi

echo "Done. $COPIES file(s) copied."
if [[ $COPIES -gt 0 ]]; then
  echo ""
  echo "Next: run setup-github-env.sh to push the cert-based secrets to GitHub."
fi
