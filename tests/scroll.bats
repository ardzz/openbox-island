# tests/scroll.bats
setup() {
  load helpers
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export FAKE_PACTL_LOG="$BATS_TEST_TMPDIR/pactl.log" FAKE_VOLUME=50
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_PACTL_LOG"
case $1 in
  get-sink-volume)
    [[ $# == 2 && $2 == @DEFAULT_SINK@ ]] || exit 2
    printf 'Volume: front-left: 32768 / %s%% / -18.06 dB, front-right: 49152 / 75%% / -7.50 dB\n' "$FAKE_VOLUME"
    ;;
  set-sink-mute|set-sink-volume) ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$BIN/pactl"
  export PATH="$BIN:$PATH"
}

@test "scroll up clamps volume at 100 percent" {
  export FAKE_VOLUME=98
  run "$SCRIPTS/scroll" up
  [ "$status" -eq 0 ]
  grep -qx 'set-sink-volume @DEFAULT_SINK@ 100%' "$FAKE_PACTL_LOG"
}

@test "scroll down clamps volume at zero" {
  export FAKE_VOLUME=3
  run "$SCRIPTS/scroll" down
  [ "$status" -eq 0 ]
  grep -qx 'set-sink-volume @DEFAULT_SINK@ 0%' "$FAKE_PACTL_LOG"
}

@test "scroll up adds five to the first channel percentage" {
  export FAKE_VOLUME=40
  run "$SCRIPTS/scroll" up
  [ "$status" -eq 0 ]
  grep -qx 'set-sink-volume @DEFAULT_SINK@ 45%' "$FAKE_PACTL_LOG"
}

@test "scroll down subtracts five and unmutes before setting volume" {
  export FAKE_VOLUME=60
  run "$SCRIPTS/scroll" down
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_PACTL_LOG")" = $'get-sink-volume @DEFAULT_SINK@\nset-sink-mute @DEFAULT_SINK@ 0\nset-sink-volume @DEFAULT_SINK@ 55%' ]
}

scroll_with_stderr() {
  "$SCRIPTS/scroll" "$@" 2> "$BATS_TEST_TMPDIR/stderr"
}

@test "invalid scroll direction reports usage on stderr without calling pactl" {
  run scroll_with_stderr sideways
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  grep -qi 'usage\|penggunaan' "$BATS_TEST_TMPDIR/stderr"
  [ ! -e "$FAKE_PACTL_LOG" ]
}

@test "missing or extra scroll arguments report usage without calling pactl" {
  run scroll_with_stderr
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  grep -qi 'usage\|penggunaan' "$BATS_TEST_TMPDIR/stderr"
  [ ! -e "$FAKE_PACTL_LOG" ]
  run scroll_with_stderr up extra
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  grep -qi 'usage\|penggunaan' "$BATS_TEST_TMPDIR/stderr"
  [ ! -e "$FAKE_PACTL_LOG" ]
}

@test "overlapping scroll invocations preserve both steps without taking the island lock" {
  export SCROLL_FIXTURE="$BATS_TEST_TMPDIR"
  printf '50\n' > "$SCROLL_FIXTURE/volume"
  mkfifo "$SCROLL_FIXTURE/reads" "$SCROLL_FIXTURE/release"
  exec {reads_fd}<> "$SCROLL_FIXTURE/reads"
  exec {release_fd}<> "$SCROLL_FIXTURE/release"
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
case $1 in
  get-sink-volume)
    read -r volume < "$SCROLL_FIXTURE/volume"
    printf '%s\n' "$volume" > "$SCROLL_FIXTURE/reads"
    read -r -t 2 _ < "$SCROLL_FIXTURE/release" || exit 1
    printf 'Volume: front-left: 32768 / %s%% / -18 dB\n' "$volume"
    ;;
  set-sink-mute) ;;
  set-sink-volume) printf '%s\n' "${3%%%}" > "$SCROLL_FIXTURE/volume" ;;
  *) exit 2 ;;
esac
EOF
  mkdir -p "$XDG_RUNTIME_DIR/eww-island"
  exec {island_fd}> "$XDG_RUNTIME_DIR/eww-island/lock"
  flock "$island_fd"
  "$SCRIPTS/scroll" up &
  first_pid=$!
  "$SCRIPTS/scroll" up &
  second_pid=$!
  IFS= read -r -t 1 -u "$reads_fd" volume
  [ "$volume" -eq 50 ]
  if IFS= read -r -t 0.1 -u "$reads_fd" volume; then
    printf 'go\ngo\n' >&"$release_fd"
    wait "$first_pid"
    wait "$second_pid"
    [ "$(cat "$SCROLL_FIXTURE/volume")" -eq 60 ]
  else
    printf 'go\n' >&"$release_fd"
    IFS= read -r -t 1 -u "$reads_fd" volume
    printf 'go\n' >&"$release_fd"
    wait "$first_pid"
    wait "$second_pid"
    [ "$volume" -eq 55 ]
    [ "$(cat "$SCROLL_FIXTURE/volume")" -eq 60 ]
  fi
}
