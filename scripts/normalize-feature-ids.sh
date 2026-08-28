#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
JQ_FILTER="${SCRIPT_DIR}/normalize-feature-ids.jq"

usage() {
  cat <<EOF
Usage:
  $0 input.geojson output.geojson

Normalize GeoJSON feature IDs for Tippecanoe

OSM string IDs are converted to unique numeric IDs while preserving the
original value in properties["@id"]
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

if [ $# -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
  usage
  exit 0
fi

[ $# -eq 2 ] || {
  usage >&2
  exit 1
}

INPUT="$1"
OUTPUT="$2"

command -v jq >/dev/null 2>&1 ||
  die "jq is required but not installed"

[ -f "${INPUT}" ] ||
  die "file not found: ${INPUT}"

[ -f "${JQ_FILTER}" ] ||
  die "jq filter not found: ${JQ_FILTER}"

if ! jq -c -f "${JQ_FILTER}" "${INPUT}" > "${OUTPUT}"; then
  rm -f "${OUTPUT}"
  die "could not normalize ${INPUT}"
fi
