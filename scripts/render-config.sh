#!/usr/bin/env bash

set -euo pipefail

: "${TILESET_ID:?TILESET_ID is required}"
: "${TILESET_NAME:=${TILESET_ID}}"
: "${TILESET_DESCRIPTION:=}"
: "${TILESET_ATTRIBUTION:=}"
: "${LAYER_NAME:?LAYER_NAME is required}"
: "${EXTRA_MBTILES:=}"
: "${STYLE_TEMPLATE:=}"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

OUTPUT_DIR="${ROOT_DIR}/output"
STYLES_DIR="${OUTPUT_DIR}/styles"
TILES_DIR="${OUTPUT_DIR}/tiles"
TEMPLATES_DIR="${ROOT_DIR}/input/style-templates"

DEFAULT_TEMPLATE="${ROOT_DIR}/scripts/templates/default-style.json"
CONFIG_FILTER="${ROOT_DIR}/scripts/tileserver-config.jq"
STYLE_FILTER="${ROOT_DIR}/scripts/style-config.jq"

CONFIG_OUT="${OUTPUT_DIR}/config.json"
STYLE_OUT="${STYLES_DIR}/${TILESET_ID}.json"
EXTENT_FILE="${TILES_DIR}/${TILESET_ID}.extent.json"


die() {
  echo "Error: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || die "file not found: $1"
}

write_atomic() {
  local output="$1"
  shift

  local tmp
  tmp="$(mktemp "${output}.tmp.XXXXXX")"

  if "$@" > "${tmp}"; then
    # Container needs ownership
    chmod 644 -- "${tmp}"
    mv -- "${tmp}" "${output}"
  else
    rm -f "${tmp}"
    return 1
  fi
}


command -v jq >/dev/null 2>&1 ||
  die "jq is required"

require_file "${CONFIG_FILTER}"
require_file "${STYLE_FILTER}"

mkdir -p \
  "${OUTPUT_DIR}" \
  "${STYLES_DIR}" \
  "${TEMPLATES_DIR}"


# Map view
#
# Resolve independently:
#   1. MAP_CENTER_LON / MAP_CENTER_LAT / MAP_ZOOM
#   2. cached output/tiles/<tileset>.extent.json
#   3. built-in fallback
#
# This allows pinning MAP_ZOOM while deriving the center

VIEW_FROM_ARGS=0
VIEW_FROM_EXTENT=0

read_extent() {
  local filter="$1"
  local value

  [[ -f "${EXTENT_FILE}" ]] || return 1

  value="$(jq -r "${filter} // empty" "${EXTENT_FILE}" 2>/dev/null)" ||
    return 1

  [[ -n "${value}" ]] || return 1

  printf '%s' "${value}"
}

resolve_view_value() {
  local var_name="$1"
  local filter="$2"
  local fallback="$3"

  local current="${!var_name:-}"
  local derived

  if [[ -n "${current}" ]]; then
    VIEW_FROM_ARGS=1
    return
  fi

  if derived="$(read_extent "${filter}")"; then
    VIEW_FROM_EXTENT=1
    printf -v "${var_name}" '%s' "${derived}"
    return
  fi

  printf -v "${var_name}" '%s' "${fallback}"
}

resolve_view_value MAP_CENTER_LON '.center[0]' 0
resolve_view_value MAP_CENTER_LAT '.center[1]' 0
resolve_view_value MAP_ZOOM '.zoom' 2

for var in MAP_CENTER_LON MAP_CENTER_LAT MAP_ZOOM; do
  value="${!var}"

  if [[ ! "${value}" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    die "${var} must be a number, got '${value}'"
  fi
done


# Style template
#
# Resolve in order:
#   1. STYLE_TEMPLATE
#   2. input/style-templates/<tileset>.json
#   3. scripts/templates/default-style.json

resolve_template() {
  if [[ -n "${STYLE_TEMPLATE}" ]]; then
    if [[ "${STYLE_TEMPLATE}" == /* ]]; then
      printf '%s' "${STYLE_TEMPLATE}"
    else
      printf '%s' "${ROOT_DIR}/${STYLE_TEMPLATE}"
    fi
    return
  fi

  local per_tileset="${TEMPLATES_DIR}/${TILESET_ID}.json"

  if [[ -f "${per_tileset}" ]]; then
    printf '%s' "${per_tileset}"
    return
  fi

  printf '%s' "${DEFAULT_TEMPLATE}"
}

TEMPLATE_PATH="$(resolve_template)"
require_file "${TEMPLATE_PATH}"

if ! jq -e . "${TEMPLATE_PATH}" >/dev/null; then
  die "style template is not valid JSON: ${TEMPLATE_PATH}"
fi

USING_DEFAULT=false

if [[ "${TEMPLATE_PATH}" == "${DEFAULT_TEMPLATE}" ]]; then
  USING_DEFAULT=true
fi


# Extra MBTiles sources
for entry in ${EXTRA_MBTILES}; do
  [[ "${entry}" == *=* ]] ||
    die "EXTRA_MBTILES entry '${entry}' must be of the form id=file.mbtiles"

  id="${entry%%=*}"
  file="${entry#*=}"

  [[ -n "${id}" ]] ||
    die "EXTRA_MBTILES entry '${entry}' has an empty source id"

  [[ -n "${file}" ]] ||
    die "EXTRA_MBTILES entry '${entry}' has an empty filename"

  [[ "${id}" != "${TILESET_ID}" ]] ||
    die "EXTRA_MBTILES id '${id}' collides with TILESET_ID and would replace the primary tileset"
done


# TileServer GL config
write_atomic \
  "${CONFIG_OUT}" \
  jq -n \
    --arg tileset_id "${TILESET_ID}" \
    --arg extra_mbtiles "${EXTRA_MBTILES}" \
    -f "${CONFIG_FILTER}" ||
  die "could not render TileServer GL config"


# Style config
write_atomic \
  "${STYLE_OUT}" \
  jq \
    --arg tileset_id "${TILESET_ID}" \
    --arg tileset_name "${TILESET_NAME}" \
    --arg tileset_description "${TILESET_DESCRIPTION}" \
    --arg tileset_attribution "${TILESET_ATTRIBUTION}" \
    --arg layer_name "${LAYER_NAME}" \
    --arg center_lon "${MAP_CENTER_LON}" \
    --arg center_lat "${MAP_CENTER_LAT}" \
    --arg zoom "${MAP_ZOOM}" \
    --argjson using_default "${USING_DEFAULT}" \
    -f "${STYLE_FILTER}" \
    "${TEMPLATE_PATH}" ||
  die "could not render style from ${TEMPLATE_PATH}"


# Report
TEMPLATE_REL="${TEMPLATE_PATH#"${ROOT_DIR}/"}"
EXTENT_REL="${EXTENT_FILE#"${ROOT_DIR}/"}"

echo "Wrote output/config.json"
echo "Wrote output/styles/${TILESET_ID}.json (from ${TEMPLATE_REL})"

if [[ -n "${EXTRA_MBTILES}" ]]; then
  echo "Registered extra mbtiles sources: ${EXTRA_MBTILES}"
fi

if [[ "${VIEW_FROM_ARGS}" == "1" && "${VIEW_FROM_EXTENT}" == "1" ]]; then
  VIEW_SOURCE="MAP_* args + ${EXTENT_REL}"
elif [[ "${VIEW_FROM_EXTENT}" == "1" ]]; then
  VIEW_SOURCE="${EXTENT_REL}"
elif [[ "${VIEW_FROM_ARGS}" == "1" ]]; then
  VIEW_SOURCE="MAP_CENTER_LON / MAP_CENTER_LAT / MAP_ZOOM"
else
  VIEW_SOURCE="built-in fallback"
fi

echo \
  "Map view: ${MAP_CENTER_LON}, ${MAP_CENTER_LAT} @ zoom ${MAP_ZOOM} (from ${VIEW_SOURCE})"


RENDERED_CENTER="$(
  jq -c \
    '[(.center // [])[0], (.center // [])[1]]' \
    "${STYLE_OUT}"
)"

if [[ "${RENDERED_CENTER}" == "[0,0]" && "${VIEW_FROM_ARGS}" == "1" ]]; then
  if [[ -f "${EXTENT_FILE}" ]]; then
    RECOVERY="Unset them to use the derived view in ${EXTENT_REL}."
  else
    RECOVERY="Unset them and run 'make build' to derive the view from the data."
  fi

  cat <<EOF

Note: view is centered at [0, 0] so map may render blank. This is using an
      explicit MAP_CENTER_LON / MAP_CENTER_LAT, not the calculated view.
      ${RECOVERY}
EOF
elif [[ "${RENDERED_CENTER}" == "[0,0]" && "${VIEW_FROM_EXTENT}" == "0" ]]; then
  cat <<EOF

Note: view is centered at [0, 0] so map may render blank. No usable cached view at
      ${EXTENT_REL} - run 'make build' to generate one or set .env
      MAP_CENTER_LON / MAP_CENTER_LAT / MAP_ZOOM manually.
      To preview the derived values without building:

        bash ./scripts/get-view.sh input/geojson/${INPUT_GEOJSON:-<file>.geojson}
EOF
fi
