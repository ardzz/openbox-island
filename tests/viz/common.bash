# tests/viz/common.bash: shared setup, teardown and tool stubs of the viz tests
setup() {
load ../helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$XDG_RUNTIME_DIR/eww-island"
  export PATH="$BIN:$PATH"
  if [[ ! -f "$SCRIPTS/viz" ]]; then
    printf 'Missing production visualizer: %s/viz\n' "$SCRIPTS" >&2
    return 1
  fi
  source "$SCRIPTS/viz"
}

teardown() {
  if [[ -n ${owned_child:-} ]]; then
    kill "$owned_child" 2>/dev/null || :
    wait "$owned_child" 2>/dev/null || :
  fi
}

# The fake reports $VIZ_TEST_TMP/xrandr.out, or fails like an unreachable display.
stub_xrandr() {
  export VIZ_TEST_TMP="$BATS_TEST_TMPDIR" DISPLAY=:0
  unset ISLAND_VIZ_FPS
  cat > "$BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
[[ $* == --current ]] || exit 2
cat "$VIZ_TEST_TMP/xrandr.out"
EOF
  chmod +x "$BIN/xrandr"
  if (( $# )); then printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/xrandr.out"; fi
}

laptop_144=(
  'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767'
  'eDP-1-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm'
  '   1920x1080    144.00*+  60.00 +  59.97    59.96    59.93  '
  '   1680x1050     59.95    59.88  '
  'HDMI-1-1 disconnected (normal left inverted right x axis y axis)'
)

stub_target_tools() {
  export VIZ_TEST_OWNER=$BASHPID
  export VIZ_TEST_TMP="$BATS_TEST_TMPDIR"
  cat > "$BIN/busctl" <<'EOF'
#!/usr/bin/env bash
[[ $* == "--user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mpris.MediaPlayer2.edge.known" ]] || exit 1
printf 'u %s\n' "$VIZ_TEST_OWNER"
EOF
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
if [[ $* == '-f json list sink-inputs' ]]; then
  printf '[{"index":5,"corked":false,"properties":{"application.process.id":"%s","object.serial":"321"}}]\n' "$VIZ_TEST_OWNER"
elif [[ $* == subscribe ]]; then
  exec sleep 30
else
  exit 1
fi
EOF
  chmod +x "$BIN/busctl" "$BIN/pactl"
}
