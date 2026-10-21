# tests/position.bats
setup() {
  load helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$XDG_RUNTIME_DIR/eww-island"
  cat > "$BIN/playerctl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/playerctl.log"
if [[ "\$*" == "--player=edge.i1 position" ]]; then echo 75.402; fi
EOF
  chmod +x "$BIN/playerctl"
  PATH="$BIN:$PATH"
}

@test "position reports the island's current player in whole seconds" {
  echo edge.i1 > "$XDG_RUNTIME_DIR/eww-island/player"
  run "$SCRIPTS/position"
  [ "$output" = '{"pos":75,"text":"1:15"}' ]
}

@test "no current player reports zero without asking playerctl" {
  run "$SCRIPTS/position"
  [ "$output" = '{"pos":0,"text":"0:00"}' ]
  echo "" > "$XDG_RUNTIME_DIR/eww-island/player"
  run "$SCRIPTS/position"
  [ "$output" = '{"pos":0,"text":"0:00"}' ]
  [ ! -e "$BATS_TEST_TMPDIR/playerctl.log" ]
}
