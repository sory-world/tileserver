#!/usr/bin/env bash
set -euo pipefail

: "${INPUT_GEOJSON:?INPUT_GEOJSON is required}"
: "${TILESET_ID:?TILESET_ID is required}"
: "${LAYER_NAME:?LAYER_NAME is required}"
: "${PROJECTION:=EPSG:4326}"
: "${TIPPECANOE_ARGS:=-zg --drop-densest-as-needed --extend-zooms-if-still-dropping}"
: "${TIPP_IMAGE:=localhost/tippecanoe:${TIPPECANOE_REF:-main}}"
: "${GDAL_IMAGE:=docker.io/osgeo/gdal:alpine-small-latest}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INPUT_PATH="${ROOT_DIR}/data/input/${INPUT_GEOJSON}"
WORK_INPUT="/work/data/input/${INPUT_GEOJSON}"
OUTPUT_PATH="${ROOT_DIR}/data/tiles/${TILESET_ID}.mbtiles"
REPROJECTED_NAME=".reprojected-${TILESET_ID}.geojson"
REPROJECTED_PATH="${ROOT_DIR}/data/input/${REPROJECTED_NAME}"
WORK_REPROJECTED="/work/data/input/${REPROJECTED_NAME}"

mkdir -p "${ROOT_DIR}/data/input" "${ROOT_DIR}/data/tiles"

if [[ ! -f "${INPUT_PATH}" ]]; then
  echo "Input file not found: data/input/${INPUT_GEOJSON}" >&2
  exit 1
fi

case "${PROJECTION}" in
  EPSG:4326)
    SOURCE_FOR_TIPPECANOE="${WORK_INPUT}"
    ;;

  EPSG:3857)
    echo "Reprojecting ${INPUT_GEOJSON} from EPSG:3857 to EPSG:4326..."

    podman run --rm \
      -v "${ROOT_DIR}:/work:Z" \
      "${GDAL_IMAGE}" \
      ogr2ogr \
        -f GeoJSON \
        -s_srs EPSG:3857 \
        -t_srs EPSG:4326 \
        "${WORK_REPROJECTED}" \
        "${WORK_INPUT}"

    SOURCE_FOR_TIPPECANOE="${WORK_REPROJECTED}"
    ;;

  *)
    echo "Unsupported PROJECTION=${PROJECTION}, use EPSG:4326 or EPSG:3857." >&2
    exit 1
    ;;
esac

echo "Building data/tiles/${TILESET_ID}.mbtiles..."
echo "Layer: ${LAYER_NAME}"
echo "Tippecanoe args: ${TIPPECANOE_ARGS}"

podman run --rm \
  -v "${ROOT_DIR}:/work:Z" \
  "${TIPP_IMAGE}" \
    -f \
    -o "/work/data/tiles/${TILESET_ID}.mbtiles" \
    -l "${LAYER_NAME}" \
    -n "${TILESET_NAME:-${TILESET_ID}}" \
    -A "${TILESET_ATTRIBUTION:-}" \
    -N "${TILESET_DESCRIPTION:-}" \
    ${TIPPECANOE_ARGS} \
    "${SOURCE_FOR_TIPPECANOE}"

echo "Wrote ${OUTPUT_PATH}"
