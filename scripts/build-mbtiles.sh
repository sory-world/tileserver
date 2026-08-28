#!/usr/bin/env bash
set -euo pipefail

: "${INPUT_GEOJSON:?INPUT_GEOJSON is required}"
: "${TILESET_ID:?TILESET_ID is required}"
: "${LAYER_NAME:?LAYER_NAME is required}"
: "${PROJECTION:=EPSG:4326}"
: "${NORMALIZE_FEATURE_IDS:=0}"
: "${TIPPECANOE_ARGS:=-zg --drop-densest-as-needed --extend-zooms-if-still-dropping}"
: "${TIPP_IMAGE:=localhost/tippecanoe:${TIPPECANOE_REF:-main}}"
: "${GDAL_IMAGE:=docker.io/osgeo/gdal:alpine-small-latest}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INPUT_DIR="${ROOT_DIR}/input/geojson"
TILES_DIR="${ROOT_DIR}/output/tiles"
WORK_DIR="${ROOT_DIR}/output/.work"

INPUT_PATH="${INPUT_DIR}/${INPUT_GEOJSON}"
OUTPUT_PATH="${TILES_DIR}/${TILESET_ID}.mbtiles"

# Container side: /input (ro) /scratch (rw) /tiles (rw)
CONTAINER_INPUT="/input/${INPUT_GEOJSON}"
REPROJECTED_NAME="reprojected-${TILESET_ID}.geojson"
REPROJECTED_PATH="${WORK_DIR}/${REPROJECTED_NAME}"
CONTAINER_REPROJECTED="/scratch/${REPROJECTED_NAME}"
NORMALIZED_NAME="normalized-ids-${TILESET_ID}.geojson"
NORMALIZED_PATH="${WORK_DIR}/${NORMALIZED_NAME}"
CONTAINER_NORMALIZED="/scratch/${NORMALIZED_NAME}"

mkdir -p "${INPUT_DIR}" "${TILES_DIR}" "${WORK_DIR}"

if [[ ! -f "${INPUT_PATH}" ]]; then
  echo "Input file not found: input/geojson/${INPUT_GEOJSON}" >&2
  exit 1
fi

# Remove intermediate GeoJSON so it doesn't break future builds
SCRATCH_FILES=()

cleanup_scratch() {
  if [[ ${#SCRATCH_FILES[@]} -gt 0 ]]; then
    rm -f "${SCRATCH_FILES[@]}"
  fi
}

trap cleanup_scratch EXIT

# Tracked as both host path (for jq) and container path (for mounted tools)
HOST_SOURCE="${INPUT_PATH}"
CONTAINER_SOURCE="${CONTAINER_INPUT}"

case "${PROJECTION}" in
  EPSG:4326)
    ;;

  EPSG:3857)
    echo "Reprojecting ${INPUT_GEOJSON} from EPSG:3857 to EPSG:4326..."

    # ogr2ogr won't write over an existing GeoJSON file
    rm -f "${REPROJECTED_PATH}"
    SCRATCH_FILES+=("${REPROJECTED_PATH}")

    podman run --rm \
      -v "${INPUT_DIR}:/input:z,ro" \
      -v "${WORK_DIR}:/scratch:z" \
      "${GDAL_IMAGE}" \
      ogr2ogr \
        -f GeoJSON \
        -s_srs EPSG:3857 \
        -t_srs EPSG:4326 \
        "${CONTAINER_REPROJECTED}" \
        "${CONTAINER_INPUT}"

    HOST_SOURCE="${REPROJECTED_PATH}"
    CONTAINER_SOURCE="${CONTAINER_REPROJECTED}"
    ;;

  *)
    echo "Unsupported PROJECTION=${PROJECTION}, use EPSG:4326 or EPSG:3857." >&2
    exit 1
    ;;
esac

case "${NORMALIZE_FEATURE_IDS}" in
  1 | true | yes)
    echo "Normalizing non-numeric feature IDs..."

    SCRATCH_FILES+=("${NORMALIZED_PATH}")
    bash "${ROOT_DIR}/scripts/normalize-feature-ids.sh" \
      "${HOST_SOURCE}" \
      "${NORMALIZED_PATH}"

    HOST_SOURCE="${NORMALIZED_PATH}"
    CONTAINER_SOURCE="${CONTAINER_NORMALIZED}"
    ;;

  0 | false | no)

    SAMPLE="$(head -c 262144 "${HOST_SOURCE}" 2>/dev/null || true)"

    if grep -qE '"id"[[:space:]]*:[[:space:]]*"(node|way|relation)/[0-9]+"' <<<"${SAMPLE}"; then
      echo "Note: input has OSM-style string feature IDs."
      echo "      Re-run with NORMALIZE_FEATURE_IDS=1."
    fi
    ;;

  *)
    echo "Unsupported NORMALIZE_FEATURE_IDS=${NORMALIZE_FEATURE_IDS} - use 0 or 1." >&2
    exit 1
    ;;
esac

echo "Building output/tiles/${TILESET_ID}.mbtiles..."
echo "Layer: ${LAYER_NAME}"
echo "Tippecanoe args: ${TIPPECANOE_ARGS}"

podman run --rm \
  -v "${INPUT_DIR}:/input:z,ro" \
  -v "${WORK_DIR}:/scratch:z" \
  -v "${TILES_DIR}:/tiles:z" \
  "${TIPP_IMAGE}" \
    -f \
    -o "/tiles/${TILESET_ID}.mbtiles" \
    -l "${LAYER_NAME}" \
    -n "${TILESET_NAME:-${TILESET_ID}}" \
    -A "${TILESET_ATTRIBUTION:-}" \
    -N "${TILESET_DESCRIPTION:-}" \
    ${TIPPECANOE_ARGS} \
    "${CONTAINER_SOURCE}"

echo "Wrote ${OUTPUT_PATH}"

EXTENT_PATH="${TILES_DIR}/${TILESET_ID}.extent.json"

if bash "${ROOT_DIR}/scripts/get-view.sh" --json "${HOST_SOURCE}" \
     > "${EXTENT_PATH}.tmp"; then
  mv "${EXTENT_PATH}.tmp" "${EXTENT_PATH}"
  echo "Wrote output/tiles/${TILESET_ID}.extent.json"
else
  rm -f "${EXTENT_PATH}.tmp"
  echo "Warning: could not calculate map extent. Style center will fall back to" >&2
  echo "         .env MAP_CENTER_LON/MAP_CENTER_LAT or [0, 0]." >&2
fi
