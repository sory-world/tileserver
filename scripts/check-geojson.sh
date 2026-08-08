#!/usr/bin/env bash

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed."
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "Usage:"
  echo "  $0 file.geojson [required_property ...]"
  echo
  echo "Example:"
  echo "  $0 roads.geojson id name road_type"
  exit 1
fi

FILE="$1"
shift

REQUIRED_PROPERTIES=("$@")

if [ ! -f "$FILE" ]; then
  echo "Error: file not found: $FILE"
  exit 1
fi

echo "Checking GeoJSON: $FILE"

# Validate JSON
if ! jq empty "$FILE" >/dev/null 2>&1; then
  echo "Invalid JSON"
  exit 1
fi

echo "Valid JSON"

# Extract layer name
LAYER_NAME=$(jq -r '.name // empty' "$FILE")

if [ -z "$LAYER_NAME" ]; then
  BASENAME=$(basename "$FILE")
  LAYER_NAME="${BASENAME%.*}"
  echo "Layer name: $LAYER_NAME  (from filename)"
else
  echo "Layer name: $LAYER_NAME  (from GeoJSON .name)"
fi

# Check GeoJSON type
GEOJSON_TYPE=$(jq -r '.type // empty' "$FILE")

echo "GeoJSON type: ${GEOJSON_TYPE:-missing}"

if [ "$GEOJSON_TYPE" != "FeatureCollection" ]; then
  echo "Warning: expected type to be FeatureCollection"
fi

# Check features array
FEATURE_COUNT=$(jq '.features | length // 0' "$FILE" 2>/dev/null || echo 0)

echo "Feature count: $FEATURE_COUNT"

if [ "$FEATURE_COUNT" -eq 0 ]; then
  echo "Warning: no features found"
fi

echo
echo "Geometry types:"
jq -r '
  .features[]
  | .geometry.type // "null"
' "$FILE" | sort | uniq -c | sort -nr

echo
echo "Feature object types:"
jq -r '
  .features[]
  | .type // "missing"
' "$FILE" | sort | uniq -c | sort -nr

echo
echo "All property keys:"
jq -r '
  .features[]
  | .properties
  | keys[]
' "$FILE" 2>/dev/null | sort | uniq

# Check for missing geometries
MISSING_GEOMETRY_COUNT=$(jq '
  [.features[] | select(.geometry == null or .geometry.type == null)]
  | length
' "$FILE")

echo
echo "Features missing geometry: $MISSING_GEOMETRY_COUNT"

# Check for missing properties object
MISSING_PROPERTIES_COUNT=$(jq '
  [.features[] | select(.properties == null)]
  | length
' "$FILE")

echo "Features missing properties object: $MISSING_PROPERTIES_COUNT"

# Check required properties if supplied
if [ ${#REQUIRED_PROPERTIES[@]} -gt 0 ]; then
  echo
  echo "Required property check:"
  FAIL=0

  for PROP in "${REQUIRED_PROPERTIES[@]}"; do
    MISSING_COUNT=$(jq --arg prop "$PROP" '
      [.features[]
       | select(.properties == null or (.properties | has($prop) | not))]
      | length
    ' "$FILE")

    if [ "$MISSING_COUNT" -eq 0 ]; then
      echo "  OK: $PROP"
    else
      echo "  Missing: $PROP in $MISSING_COUNT feature(s)"
      FAIL=1
    fi
  done

  if [ "$FAIL" -eq 1 ]; then
    echo
    echo "GeoJSON failed required property checks"
    exit 2
  fi
fi

echo
echo "GeoJSON check complete"
