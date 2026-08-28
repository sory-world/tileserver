ifeq (,$(wildcard .env))
$(error .env not found - create it with: cp .env.example .env)
endif

include .env
export

TIPP_IMAGE ?= localhost/tippecanoe:$(TIPPECANOE_REF)
TILESERVER_IMAGE ?= docker.io/maptiler/tileserver-gl:latest
GDAL_IMAGE ?= docker.io/osgeo/gdal:alpine-small-latest

.PHONY: dirs tippecanoe-image config build serve clean shell

dirs:
	mkdir -p input/geojson input/style-templates output/tiles output/styles

tippecanoe-image:
	podman build \
	  --build-arg TIPPECANOE_REF="$(TIPPECANOE_REF)" \
	  -f Containerfile.tippecanoe \
	  -t "$(TIPP_IMAGE)" .

config: dirs
	bash ./scripts/render-config.sh

build: dirs tippecanoe-image
	bash ./scripts/build-mbtiles.sh
	bash ./scripts/render-config.sh

serve:
	bash ./scripts/check-serve.sh
	podman run --rm -it \
	  --name tileserver-gl \
	  -p "$(TILESERVER_PORT):8080" \
	  -v "$$(pwd)/output:/data:Z" \
	  -e TILESERVER_GL_ALLOWED_HOSTS="$(TILESERVER_ALLOWED_HOSTS)" \
	  "$(TILESERVER_IMAGE)"

clean:
	rm -f output/tiles/*.mbtiles
	rm -f output/tiles/*.extent.json
	rm -f output/config.json
	rm -f output/styles/*.json
	rm -rf output/.work
