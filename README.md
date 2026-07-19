# Tileserver

Converts GeoJSON into an MBTiles vector tileset with Tippecanoe and serves it with TileServer GL.

## Requirements
- Linux/WSL2
- Podman
- Make
- Bash
- Git (needed when building the Tippecanoe image)
- jq (used for JSON processing)

No local Tippecanoe, GDAL or TileServer GL install is required as these run in containers.

For rootless Podman make sure your user can run containers:

```bash
podman info
```

## Setup

1. Place your GeoJSON input file in `data/input/`.
2. Create `.env` file from the example:

```bash
cp .env.example .env
# Edit .env if needed
```

3. Build and serve the tileset:

```bash
make build
make serve
```

## Quick start

With input GeoJSON:

```bash
make build
make serve
```

Open TileServer GL at:

```text
http://localhost:8080
```

Vector tiles are served from:

```text
http://localhost:${TILESERVER_PORT}/data/${TILESET_ID}/{z}/{x}/{y}.pbf
```

To regenerate config with the same mbtiles:

```bash
make config
make serve
```

## Overrides

Build a different GeoJSON without editing .env:

```bash
make build \
  INPUT_GEOJSON=roads.geojson \
  TILESET_ID=roads \
  TILESET_NAME="Roads" \
  LAYER_NAME=roads
```

```bash
make build \
  INPUT_GEOJSON=buildings.geojson \
  TILESET_ID=buildings \
  LAYER_NAME=buildings \
  TIPPECANOE_ARGS="-Z10 -z15 --drop-densest-as-needed"
```

## Notes

- Perfer WGS84 GeoJSON (`EPSG:4326`) but Tippecanoe also supports `EPSG:3857`. For other CRS reproject before tiling.
- `LAYER_NAME` must match MapLibre/TileServer style `source-layer`.
- If features disappear at low zooms Tippecanoe may be dropping features to keep tile sizes small. Modify `-z`, `-Z`, `--drop-densest-as-needed`, `--extend-zooms-if-still-dropping` and use `-y` to remove unused attributes.
- For prod pin `TIPPECANOE_REF` to a tag or commit instead of `main`.
- Replace styles in `render-config.sh` (or the generated `data/styles/style.json` for testing - will be lost on rebuild) with desired MapLibre style depending on geometry types & attributes.
