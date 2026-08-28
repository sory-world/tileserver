#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="${SCRIPT_DIR}/get-view.jq"

DEFAULT_WIDTH=1024
DEFAULT_HEIGHT=768
DEFAULT_PADDING=0.05

usage() {
  cat <<EOF
Usage:
  $0 file.geojson [--json] [--width PX] [--height PX] [--padding FRACTION]

Options:
  --json             Output JSON
  --width PX         Viewport width to fit (default ${DEFAULT_WIDTH})
  --height PX        Viewport height to fit (default ${DEFAULT_HEIGHT})
  --padding FRACTION Margin per side, 0-0.4 (default ${DEFAULT_PADDING})
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

FILE=""
WIDTH="${DEFAULT_WIDTH}"
HEIGHT="${DEFAULT_HEIGHT}"
PADDING="${DEFAULT_PADDING}"
AS_JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      AS_JSON=1
      shift
      ;;
    --width)
      [ $# -ge 2 ] || die "--width needs a value"
      WIDTH="$2"
      shift 2
      ;;
    --height)
      [ $# -ge 2 ] || die "--height needs a value"
      HEIGHT="$2"
      shift 2
      ;;
    --padding)
      [ $# -ge 2 ] || die "--padding needs a value"
      PADDING="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [ -z "${FILE}" ] || die "unexpected argument: $1"
      FILE="$1"
      shift
      ;;
  esac
done

[ -n "${FILE}" ] || {
  usage >&2
  exit 1
}

[ -f "${FILE}" ] || die "file not found: ${FILE}"
[ -f "${JQ_FILTER}" ] || die "jq filter not found: ${JQ_FILTER}"

command -v jq >/dev/null 2>&1 ||
  die "jq is required but not installed"

[[ "${WIDTH}" =~ ^[1-9][0-9]*$ ]] ||
  die "--width must be a positive integer"

[[ "${HEIGHT}" =~ ^[1-9][0-9]*$ ]] ||
  die "--height must be a positive integer"

awk -v p="${PADDING}" '
  BEGIN {
    valid = p ~ /^([0-9]+([.][0-9]*)?|[.][0-9]+)$/
    exit !(valid && p >= 0 && p <= 0.4)
  }
' || die "--padding must be between 0 and 0.4"

if ! EXTENT=$(
  jq -c \
    --argjson width "${WIDTH}" \
    --argjson height "${HEIGHT}" \
    --argjson padding "${PADDING}" \
    -f "${JQ_FILTER}" \
    "${FILE}"
); then
  die "could not parse ${FILE} as GeoJSON"
fi

[ "${EXTENT}" != "null" ] ||
  die "no coordinates found in ${FILE}"

if [ "${AS_JSON}" -eq 1 ]; then
  printf '%s\n' "${EXTENT}"
  exit 0
fi

IFS=$'\t' read -r \
  WEST SOUTH EAST NORTH \
  LON LAT ZOOM \
  LON_SPAN LAT_SPAN \
  < <(
    jq -r '[.bounds[], .center[], .zoom, .span[]] | @tsv' \
      <<<"${EXTENT}"
  )

cat <<EOF
Extent of ${FILE}

  Bounds (W S E N): ${WEST}, ${SOUTH}, ${EAST}, ${NORTH}
  Span (degrees):   ${LON_SPAN} lon x ${LAT_SPAN} lat
  Fits ${WIDTH}x${HEIGHT} px at zoom ${ZOOM} (padding ${PADDING} per side)

make build caches this automatically. To pin it instead add values to .env:

MAP_CENTER_LON=${LON}
MAP_CENTER_LAT=${LAT}
MAP_ZOOM=${ZOOM}
EOF

if awk -v span="${LON_SPAN}" 'BEGIN { exit !(span > 180) }'; then
  cat <<EOF

Warning: longitude span exceeds 180 degrees.
         If this data crosses the antimeridian the calculated center is wrong.
         Set MAP_CENTER_LON manually in .env.
EOF
fi
