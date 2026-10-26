# tests/media/common.bash: shared setup and helpers of the media tests
setup() {
load ../helpers
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  STATE="$XDG_RUNTIME_DIR/eww-island"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  PATH="$BIN:$PATH"
  source "$SCRIPTS/media"
}
# line FIELD...: one playerctl --format line (fields joined by \x1f).
line() { local IFS=$'\x1f'; printf '%s' "$*"; }

require_imagemagick() {
  IMAGE_TOOL=$(command -v magick || command -v convert) || skip "ImageMagick (magick atau convert) tidak tersedia"
}

# listener PLAYERCTL_BODY: run the media listener on a fake playerctl; island calls go to island.log.
listener() {
  mkdir -p "$BATS_TEST_TMPDIR/eww"
  cp -r "$SCRIPTS" "$BATS_TEST_TMPDIR/eww/scripts"
  cp "$REPO/eww/players" "$BATS_TEST_TMPDIR/eww/players"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/island.log"\n' "$BATS_TEST_TMPDIR" \
    > "$BATS_TEST_TMPDIR/eww/scripts/island"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$BIN/playerctl"
  chmod +x "$BATS_TEST_TMPDIR/eww/scripts/island" "$BIN/playerctl"
  touch "$BATS_TEST_TMPDIR/island.log"
}
