# Convert whitespace-separated EXTRA_MBTILES value into TileServer GL sources
# labels=labels.mbtiles boundaries=boundaries.mbtiles

def extra_sources:
  [
    $extra_mbtiles
    | scan("\\S+")
    | capture("^(?<id>[^=]+)=(?<file>.+)$")
  ]
  | reduce .[] as $entry ({};
      . + {
        ($entry.id): {
          mbtiles: $entry.file
        }
      }
    );

{
  options: {
    paths: {
      root: "",
      styles: "styles",
      mbtiles: "tiles"
    },
    frontPage: true,
    serveAllStyles: true,
    serveAllFonts: true
  },

  data: (
    {
      ($tileset_id): {
        mbtiles: ($tileset_id + ".mbtiles")
      }
    }
    + extra_sources
  ),

  styles: {
    ($tileset_id): {
      style: ($tileset_id + ".json"),
      serve_rendered: false
    }
  }
}
