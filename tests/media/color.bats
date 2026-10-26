# tests/media/color.bats: cover tint extraction and content-addressed cache
load common

setup() {
  load ../helpers
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  source "$SCRIPTS/media"
}

color_covers() {
  require_imagemagick
  "$IMAGE_TOOL" -size 12x12 xc:'#cc2222' "$BATS_TEST_TMPDIR/red.png"
  "$IMAGE_TOOL" -size 12x12 xc:'#2244cc' "$BATS_TEST_TMPDIR/blue.png"
  "$IMAGE_TOOL" -size 12x12 xc:'#888888' "$BATS_TEST_TMPDIR/grey.png"
}

@test "a red cover yields a normalized red tint" {
  color_covers
  run art_color "$BATS_TEST_TMPDIR/red.png"
  [ "$status" -eq 0 ]
  [[ $output =~ ^#[0-9a-f]{6}$ ]]
  [ "$output" = '#cc2222' ]
}

@test "a blue cover yields a normalized blue tint" {
  color_covers
  run art_color "$BATS_TEST_TMPDIR/blue.png"
  [ "$status" -eq 0 ]
  [ "$output" = '#2244cc' ]
}

@test "a grey cover has no tint" {
  color_covers
  run art_color "$BATS_TEST_TMPDIR/grey.png"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "a mostly grey cover does not tint from a small colored patch" {
  color_covers
  "$IMAGE_TOOL" "$BATS_TEST_TMPDIR/grey.png" -fill '#cc2222' -draw 'rectangle 0,0 1,1' "$BATS_TEST_TMPDIR/mixed.png"
  run art_color "$BATS_TEST_TMPDIR/mixed.png"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "missing and corrupt covers return empty without failing the caller" {
  run art_color "$BATS_TEST_TMPDIR/missing.png"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
  printf 'not an image' > "$BATS_TEST_TMPDIR/corrupt.png"
  run art_color "$BATS_TEST_TMPDIR/corrupt.png"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "identical cover contents reuse the cache without magick even after the path rotates" {
  color_covers
  run art_color "$BATS_TEST_TMPDIR/red.png"
  [ "$status" -eq 0 ]
  first=$output
  [ "$first" = '#cc2222' ]
  key=$(sha1sum < "$BATS_TEST_TMPDIR/red.png"); key=${key%% *}
  cache="$XDG_CACHE_HOME/eww-island/art-color/$key"
  [ -f "$cache" ]
  [ "$(cat "$cache")" = "$first" ]
  mv "$BATS_TEST_TMPDIR/red.png" "$BATS_TEST_TMPDIR/rotated.png"
  ln -s "$(command -v sha1sum)" "$BIN/sha1sum"
  PATH="$BIN" run art_color "$BATS_TEST_TMPDIR/rotated.png"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "a saturated twelve-hue rainbow has a tint despite its dispersed hue weights" {
  require_imagemagick
  local hue
  local -a stripes=()
  for hue in 15 45 75 105 135 165 195 225 255 285 315 345; do
    stripes+=("xc:hsv($hue,90%,100%)")
  done
  "$IMAGE_TOOL" -size 1x12 "${stripes[@]}" +append "$BATS_TEST_TMPDIR/rainbow.png"
  run art_color "$BATS_TEST_TMPDIR/rainbow.png"
  [ "$status" -eq 0 ]
  [[ $output =~ ^#[0-9a-f]{6}$ ]]
}

@test "a garbage cache entry is regenerated from the artwork" {
  color_covers
  key=$(sha1sum < "$BATS_TEST_TMPDIR/red.png"); key=${key%% *}
  cache="$XDG_CACHE_HOME/eww-island/art-color/$key"
  mkdir -p "${cache%/*}"
  printf 'garbage\n' > "$cache"
  run art_color "$BATS_TEST_TMPDIR/red.png"
  [ "$status" -eq 0 ]
  [ "$output" = '#cc2222' ]
  [ "$(cat "$cache")" = '#cc2222' ]
}

@test "an empty cache file is a valid grey result without magick" {
  color_covers
  key=$(sha1sum < "$BATS_TEST_TMPDIR/grey.png"); key=${key%% *}
  cache="$XDG_CACHE_HOME/eww-island/art-color/$key"
  mkdir -p "${cache%/*}"
  touch "$cache"
  ln -s "$(command -v sha1sum)" "$BIN/sha1sum"
  PATH="$BIN" run art_color "$BATS_TEST_TMPDIR/grey.png"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "an uncached cover has no tint without either ImageMagick command" {
  printf 'P3\n1 1\n255\n204 34 34\n' > "$BATS_TEST_TMPDIR/red.ppm"
  ln -s "$(command -v sha1sum)" "$BIN/sha1sum"
  PATH="$BIN" run art_color "$BATS_TEST_TMPDIR/red.ppm"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "convert extracts a tint when magick is absent" {
  local convert tool
  convert=$(command -v convert) || skip "ImageMagick convert tidak tersedia"
  printf 'P3\n1 1\n255\n204 34 34\n' > "$BATS_TEST_TMPDIR/red.ppm"
  ln -s "$convert" "$BIN/convert"
  for tool in sha1sum awk mkdir mktemp mv; do
    ln -s "$(command -v "$tool")" "$BIN/$tool"
  done
  PATH="$BIN" run art_color "$BATS_TEST_TMPDIR/red.ppm"
  [ "$status" -eq 0 ]
  [ "$output" = '#cc2222' ]
}
