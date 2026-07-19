#!/usr/bin/env bash
set -euo pipefail

: "${TILESET_ID:?TILESET_ID is required}"
: "${TILESET_NAME:=${TILESET_ID}}"
: "${TILESET_DESCRIPTION:=}"
: "${TILESET_ATTRIBUTION:=}"
: "${LAYER_NAME:?LAYER_NAME is required}"
: "${MAP_CENTER_LON:=0}"
: "${MAP_CENTER_LAT:=0}"
: "${MAP_ZOOM:=2}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${ROOT_DIR}/data"
STYLES_DIR="${ROOT_DIR}/data/styles"

mkdir -p "${CONFIG_DIR}" "${STYLES_DIR}"

json_escape() {
  printf '%s' "$1" \
    | sed \
      -e 's/\\/\\\\/g' \
      -e 's/"/\\"/g' \
      -e ':a;N;$!ba;s/\n/\\n/g'
}

TILESET_ID_JSON="$(json_escape "${TILESET_ID}")"
TILESET_NAME_JSON="$(json_escape "${TILESET_NAME}")"
TILESET_DESCRIPTION_JSON="$(json_escape "${TILESET_DESCRIPTION}")"
TILESET_ATTRIBUTION_JSON="$(json_escape "${TILESET_ATTRIBUTION}")"
LAYER_NAME_JSON="$(json_escape "${LAYER_NAME}")"

cat > "${CONFIG_DIR}/config.json" <<EOF
{
  "options": {
    "paths": {
      "root": "",
      "styles": "styles",
      "mbtiles": "tiles"
    },
    "frontPage": true,
    "serveAllStyles": true,
    "serveAllFonts": true
  },
  "data": {
    "${TILESET_ID_JSON}": {
      "mbtiles": "${TILESET_ID_JSON}.mbtiles"
    }
  },
  "styles": {
    "${TILESET_ID_JSON}": {
      "style": "${TILESET_ID_JSON}.json",
      "serve_rendered": false
    }
  }
}
EOF

cat > "${STYLES_DIR}/${TILESET_ID}.json" <<EOF
{
  "version": 8,
  "center": [${MAP_CENTER_LON}, ${MAP_CENTER_LAT}],
  "zoom": ${MAP_ZOOM},
  "name": "${TILESET_NAME_JSON}",
  "metadata": {
    "description": "${TILESET_DESCRIPTION_JSON}",
    "attribution": "${TILESET_ATTRIBUTION_JSON}"
  },
  "sources": {
    "${TILESET_ID_JSON}": {
      "type": "vector",
      "url": "mbtiles://{${TILESET_ID_JSON}}"
    }
  },
  "layers": [
    {
      "id": "${LAYER_NAME_JSON}-polygons",
      "type": "fill",
      "source": "${TILESET_ID_JSON}",
      "source-layer": "${LAYER_NAME_JSON}",
      "filter": ["==", ["geometry-type"], "Polygon"],
      "paint": {
        "fill-color": "#3bb2d0",
        "fill-opacity": 0.4
      }
    },
    {
      "id": "${LAYER_NAME_JSON}-lines",
      "type": "line",
      "source": "${TILESET_ID_JSON}",
      "source-layer": "${LAYER_NAME_JSON}",
      "filter": ["==", ["geometry-type"], "LineString"],
      "paint": {
        "line-color": "#3bb2d0",
        "line-width": 2
      }
    },
    {
      "id": "${LAYER_NAME_JSON}-points",
      "type": "circle",
      "source": "${TILESET_ID_JSON}",
      "source-layer": "${LAYER_NAME_JSON}",
      "filter": ["==", ["geometry-type"], "Point"],
      "paint": {
        "circle-radius": 5,
        "circle-color": "#3bb2d0",
        "circle-stroke-width": 1,
        "circle-stroke-color": "#ffffff"
      }
    }
  ]
}
EOF

echo "Wrote data/config.json"
echo "Wrote data/styles/${TILESET_ID}.json"
