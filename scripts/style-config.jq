def subst_string:
  gsub("\\{\\{TILESET_ID\\}\\}"; $tileset_id)
  | gsub("\\{\\{TILESET_NAME\\}\\}"; $tileset_name)
  | gsub("\\{\\{TILESET_DESCRIPTION\\}\\}"; $tileset_description)
  | gsub("\\{\\{TILESET_ATTRIBUTION\\}\\}"; $tileset_attribution)
  | gsub("\\{\\{LAYER_NAME\\}\\}"; $layer_name);

def subst_strings:
  walk(
    if type == "string" then
      subst_string
    elif type == "object" then
      with_entries(.key |= subst_string)
    else
      .
    end
  );

# Convert numeric placeholder strings into JSON numbers
def subst_number($token; $value):
  walk(
    if . == $token then
      ($value | tonumber)
    else
      .
    end
  );


subst_strings

| subst_number("{{MAP_CENTER_LON}}"; $center_lon)
| subst_number("{{MAP_CENTER_LAT}}"; $center_lat)
| subst_number("{{MAP_ZOOM}}"; $zoom)

| if $using_default then
    .center = [
      ($center_lon | tonumber),
      ($center_lat | tonumber)
    ]
    | .zoom = ($zoom | tonumber)
  else
    .
  end
