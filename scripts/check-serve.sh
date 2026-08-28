#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required (see README dependencies)." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT_DIR}/output/config.json"
TILES_DIR="${ROOT_DIR}/output/tiles"
STYLES_DIR="${ROOT_DIR}/output/styles"

if [[ ! -f "${CONFIG}" ]]; then
  echo "output/config.json not found. Run 'make config' (or 'make build') first." >&2
  exit 1
fi

if ! jq -e . "${CONFIG}" >/dev/null 2>&1; then
  echo "output/config.json is not valid JSON. Re-run 'make config'." >&2
  exit 1
fi

check_file() {
  local kind="$1" dir="$2" name="$3"

  if [[ -z "${name}" ]]; then
    return 0
  fi
  if [[ "${name}" == http://* || "${name}" == https://* || "${name}" == s3://* ]]; then
    return 0
  fi
  if [[ ! -f "${dir}/${name}" ]]; then
    echo "Missing ${kind}: ${dir#"${ROOT_DIR}"/}/${name}" >&2
    return 1
  fi
  return 0
}

status=0

while IFS= read -r name; do
  check_file "tileset" "${TILES_DIR}" "${name}" || status=1
done < <(jq -r '.data // {} | .[].mbtiles // empty' "${CONFIG}")

while IFS= read -r name; do
  check_file "style" "${STYLES_DIR}" "${name}" || status=1
done < <(jq -r '.styles // {} | .[].style // empty' "${CONFIG}")

if [[ "${status}" -ne 0 ]]; then
  cat >&2 <<'EOF'

Files needed for tileserver-gl to start are not present:
  - run 'make build' to generate the primary tileset
  - build the tilesets listed in EXTRA_MBTILES and put in output/tiles/
  - re-run 'make config' without missing EXTRA_MBTILES entries
EOF
  exit 1
fi
