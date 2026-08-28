# OSM IDs are converted while retaining the original string in properties["@id"]:
#   node/N     -> N * 4 + 0
#   way/N      -> N * 4 + 1
#   relation/N -> N * 4 + 2

def is_osm_id:
  test("^(node|way|relation)/[0-9]+$");

def osm_numeric_id:
  capture("^(?<type>node|way|relation)/(?<number>[0-9]+)$")
  | (.number | tonumber) * 4
    + (
        if .type == "node" then 0
        elif .type == "way" then 1
        else 2
        end
      );

def normalize_id:
  if has("id") | not then
    .

  # Positive integer IDs are valid
  elif (.id | type) == "number"
       and .id >= 0
       and (.id | floor) == .id
  then
    .

  else
    (.id | tostring) as $original
    | (
        if $original | is_osm_id
        then $original | osm_numeric_id
        else null
        end
      ) as $numeric

    # Preserve the original ID unless @id already exists
    | .properties = (
        (.properties // {})
        | if has("@id")
          then .
          else .["@id"] = $original
          end
      )

    # Unknown string IDs cannot be represented
    | if $numeric == null
      then del(.id)
      else .id = $numeric
      end
  end;


if .type == "FeatureCollection" then
  .features |= map(normalize_id)
else
  normalize_id
end
