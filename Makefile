include .env
export

TIPP_IMAGE ?= localhost/tippecanoe:$(TIPPECANOE_REF)
TILESERVER_IMAGE ?= docker.io/maptiler/tileserver-gl:latest
GDAL_IMAGE ?= docker.io/osgeo/gdal:alpine-small-latest

.PHONY: dirs tippecanoe-image config build serve clean shell

dirs:
	mkdir -p data/input data/tiles data/styles

tippecanoe-image:
	podman build \
	  --build-arg TIPPECANOE_REF="$(TIPPECANOE_REF)" \
	  -f Containerfile.tippecanoe \
	  -t "$(TIPP_IMAGE)" .

config: dirs
	bash ./scripts/render-config.sh

build: dirs tippecanoe-image config
	bash ./scripts/build-mbtiles.sh

serve:
	podman run --rm -it \
	  --name tileserver-gl \
	  -p "$(TILESERVER_PORT):8080" \
	  -v "$$(pwd)/data:/data:Z" \
	  -e TILESERVER_GL_ALLOWED_HOSTS="$(TILESERVER_ALLOWED_HOSTS)" \
	  "$(TILESERVER_IMAGE)"

clean:
	rm -f data/tiles/*.mbtiles
	rm -f data/config.json
	rm -f data/styles/*.json
