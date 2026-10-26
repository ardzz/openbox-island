# tests/media/color.bats: cover tint extraction and content-addressed cache
load common

setup() {
  load ../helpers
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  source "$SCRIPTS/media"
  magick -size 12x12 xc:'#cc2222' "$BATS_TEST_TMPDIR/red.png"
  magick -size 12x12 xc:'#2244cc' "$BATS_TEST_TMPDIR/blue.png"
  magick -size 12x12 xc:'#888888' "$BATS_TEST_TMPDIR/grey.png"
}

@test "a red cover yields a normalized red tint" {
  run art_color "$BATS_TEST_TMPDIR/red.png"
  [ "$status" -eq 0 ]
  [[ $output =~ ^#[0-9a-f]{6}$ ]]
  [ "$output" = '#cc2222' ]
}

@test "a blue cover yields a normalized blue tint" {
  run art_color "$BATS_TEST_TMPDIR/blue.png"
  [ "$status" -eq 0 ]
  [ "$output" = '#2244cc' ]
}

@test "a grey cover has no tint" {
  run art_color "$BATS_TEST_TMPDIR/grey.png"
  [ "$status" -eq 0 ]
  [ "$output" = '' ]
}

@test "a mostly grey cover does not tint from a small colored patch" {
  magick "$BATS_TEST_TMPDIR/grey.png" -fill '#cc2222' -draw 'rectangle 0,0 1,1' "$BATS_TEST_TMPDIR/mixed.png"
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
