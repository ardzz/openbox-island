# tests/launcher.bats
setup() {
  load helpers
  export HOME="$BATS_TEST_TMPDIR/home" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$HOME"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/dunstify.log"\n' "$BATS_TEST_TMPDIR" > "$BIN/dunstify"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/eww.log"\n' "$BATS_TEST_TMPDIR" > "$BIN/eww"
  chmod +x "$BIN/dunstify" "$BIN/eww"
  PATH="$BIN:$PATH"
}

@test "a missing island config notifies and starts no daemon" {
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 1 ]
  grep -q 'island gagal' "$BATS_TEST_TMPDIR/dunstify.log"
  [ ! -e "$BATS_TEST_TMPDIR/eww.log" ]
}

delayed_eww() {
  mkdir -p "$HOME/.config/eww-island" "$XDG_RUNTIME_DIR/eww-island"
  touch "$HOME/.config/eww-island/eww.yuck"
  export FAKE_LAUNCH_STATE="$BATS_TEST_TMPDIR/shutdown" FAKE_LAUNCH_LOG="$BATS_TEST_TMPDIR/events"
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
[[ $1 == --config && $2 == "$HOME/.config/eww-island" ]] || exit 2
shift 2
case $1 in
  kill) echo "${FAKE_SHUTDOWN_POLLS:-3}" > "$FAKE_LAUNCH_STATE"; echo kill >> "$FAKE_LAUNCH_LOG" ;;
  ping)
    read -r remaining < "$FAKE_LAUNCH_STATE"
    if (( remaining > 0 )); then
      echo $((remaining - 1)) > "$FAKE_LAUNCH_STATE"
      echo stopping >> "$FAKE_LAUNCH_LOG"
    elif (( remaining == 0 )); then
      echo unreachable >> "$FAKE_LAUNCH_LOG"; exit 1
    fi ;;
  daemon)
    echo daemon >> "$FAKE_LAUNCH_LOG"
    echo -1 > "$FAKE_LAUNCH_STATE" ;;
  open) echo "$*" >> "$FAKE_LAUNCH_LOG" ;;
esac
EOF
  chmod +x "$BIN/eww"
}

@test "restart waits for shutdown before starting the daemon and opening island" {
  delayed_eww
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -E '^(unreachable|daemon|open)' "$FAKE_LAUNCH_LOG" | uniq)" = $'unreachable\ndaemon\nopen island' ]
}

@test "stop kills only the island config and removes state even when already stopped" {
  delayed_eww
  run "$REPO/openbox/island.sh" stop
  [ "$status" -eq 0 ]
  [ ! -d "$XDG_RUNTIME_DIR/eww-island" ]
  [ "$(uniq "$FAKE_LAUNCH_LOG")" = $'kill\nstopping\nunreachable' ]
  export FAKE_SHUTDOWN_POLLS=0
  run "$REPO/openbox/island.sh" stop
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/dunstify.log" ]
}

@test "a daemon that never stops fails without starting a replacement" {
  delayed_eww
  export FAKE_SHUTDOWN_POLLS=100
  run "$REPO/openbox/island.sh"
  [ "$status" -eq 1 ]
  [[ $output == *"daemon lama tidak berhenti"* ]]
  ! grep -qx daemon "$FAKE_LAUNCH_LOG"
  [ -d "$XDG_RUNTIME_DIR/eww-island" ]
}
