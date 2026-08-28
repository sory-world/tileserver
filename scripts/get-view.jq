# Round avoiding -0
def round_to($dp):
  pow(10; $dp) as $scale
  | ((. * $scale | round) / $scale)
  | if . == 0 then 0 else . end;

def pi:
  1 | atan * 4;

# Latitude -> Web Mercator Y
def mercator_y:
  (. * pi / 180) as $rad
  | (1 - (
      ((($rad | tan) + (1 / ($rad | cos))) | log)
      / pi
    )) / 2;

# Web Mercator Y -> latitude
def inverse_mercator_y:
  pi as $pi
  | ((($pi * (1 - 2 * .)) | sinh | atan) * 180 / $pi);

# Recursively extract [lon, lat]
def positions:
  if type != "array" then
    empty
  elif length >= 2
       and (.[0] | type) == "number"
       and (.[1] | type) == "number"
  then
    [.[0], .[1]]
  else
    .[] | positions
  end;

def geometry_positions:
  if . == null then
    empty
  elif .type == "GeometryCollection" then
    (.geometries // [])[] | geometry_positions
  else
    (.coordinates // empty) | positions
  end;

# Accept FeatureCollection, Feature, bare Geometry
def all_positions:
  (
    if .type == "FeatureCollection" then
      (.features // [])[].geometry
    elif .type == "Feature" then
      .geometry
    else
      .
    end
  )
  | geometry_positions;

def bounds:
  reduce all_positions as $p (
    null;

    if . == null then
      {
        w: $p[0],
        s: $p[1],
        e: $p[0],
        n: $p[1]
      }
    else
      {
        w: ([.w, $p[0]] | min),
        s: ([.s, $p[1]] | min),
        e: ([.e, $p[0]] | max),
        n: ([.n, $p[1]] | max)
      }
    end
  );

def zoom_for($pixels; $fraction):
  if $fraction <= 0 then
    99
  else
    ($pixels / (512 * $fraction) | log2)
  end;


($width  * (1 - 2 * $padding)) as $fit_width
| ($height * (1 - 2 * $padding)) as $fit_height
| bounds

| if . == null then
    null
  else
    . as $b

    | (($b.e - $b.w) / 360) as $lon_fraction
    | ((($b.s | mercator_y) - ($b.n | mercator_y)) | fabs)
      as $lat_fraction

    | zoom_for($fit_width; $lon_fraction) as $zoom_x
    | zoom_for($fit_height; $lat_fraction) as $zoom_y

    | (
        if $lon_fraction <= 0 and $lat_fraction <= 0 then
          14
        else
          ([$zoom_x, $zoom_y, 22] | min)
        end
      ) as $zoom

    | {
        bounds: [
          $b.w,
          $b.s,
          $b.e,
          $b.n
        ],

        center: [
          ((($b.w + $b.e) / 2) | round_to(6)),
          (
            ((($b.n | mercator_y) + ($b.s | mercator_y)) / 2)
            | inverse_mercator_y
            | round_to(6)
          )
        ],

        zoom: (($zoom * 100 | floor) / 100),

        span: [
          (($b.e - $b.w) | round_to(6)),
          (($b.n - $b.s) | round_to(6))
        ],

        viewport: {
          width: $width,
          height: $height,
          padding: $padding
        }
      }
  end
