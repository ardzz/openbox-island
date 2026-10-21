# tests/island.bats
setup() {
  load helpers
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" EXPECTED_CFG="$REPO/eww"
  export FAKE_EWW_LOG="$BATS_TEST_TMPDIR/eww.log" FAKE_EWW_ACTIVE="$BATS_TEST_TMPDIR/active"
  export FAKE_POINTER="$BATS_TEST_TMPDIR/pointer"
  ST="$XDG_RUNTIME_DIR/eww-island"
  : > "$FAKE_EWW_LOG"; printf 'island: island\n' > "$FAKE_EWW_ACTIVE"; away
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FAKE_EWW_LOG"; exit 1; fi
case $1 in
  active-windows) cat "$FAKE_EWW_ACTIVE"; exit 0 ;;
  open) sleep "${FAKE_EWW_OPEN_DELAY:-0}"; printf '%s: %s\n' "$2" "$2" >> "$FAKE_EWW_ACTIVE"
        if [[ -n $FAKE_POINTER_AFTER_OPEN ]]; then echo "$FAKE_POINTER_AFTER_OPEN" > "$FAKE_POINTER"; fi ;;
  close) grep -vx "$2: $2" "$FAKE_EWW_ACTIVE" > "$FAKE_EWW_ACTIVE.tmp"; mv "$FAKE_EWW_ACTIVE.tmp" "$FAKE_EWW_ACTIVE" ;;
esac
printf '%s\n' "$*" >> "$FAKE_EWW_LOG"
EOF
  # Fake xdotool: the pointer comes from $FAKE_POINTER; the visible island windows from eww's
  # active windows, at their real geometry (compact 240x36+840+8, expanded 420x156+750+8).
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "getmouselocation --shell")
    read -r x y < "$FAKE_POINTER"; printf 'X=%s\nY=%s\nSCREEN=0\nWINDOW=1\n' "$x" "$y" ;;
  "search --onlyvisible --name ^Eww - island(-expanded)?\$ getwindowgeometry --shell %@")
    grep -qx 'island: island' "$FAKE_EWW_ACTIVE" && printf 'WINDOW=2\nX=840\nY=8\nWIDTH=240\nHEIGHT=36\nSCREEN=0\n'
    grep -qx 'island-expanded: island-expanded' "$FAKE_EWW_ACTIVE" && printf 'WINDOW=3\nX=750\nY=8\nWIDTH=420\nHEIGHT=156\nSCREEN=0\n'
    exit 0 ;;
  *) echo "unexpected xdotool $*" >> "$FAKE_EWW_LOG"; exit 1 ;;
esac
EOF
  chmod +x "$BIN/eww" "$BIN/xdotool"
  PATH="$BIN:$PATH"
  OPEN=$'update island_reveal=false\nopen island-expanded\nupdate island_reveal=true'
  CLOSE=$'update island_reveal=false\nclose island-expanded'
}
calls() { cat "$FAKE_EWW_LOG"; }
expanded() { printf 'island: island\nisland-expanded: island-expanded\n' > "$FAKE_EWW_ACTIVE"; }
on_compact() { echo '960 26' > "$FAKE_POINTER"; }
on_expanded_only() { echo '1160 150' > "$FAKE_POINTER"; }
away() { echo '960 700' > "$FAKE_POINTER"; }
auto_running() { mkdir -p "$ST"; echo $(( $(date +%s) + 60 )) > "$ST/auto_until"; }
stub_hover_sleep() {
  export FAKE_SLEEP_LOG="$BATS_TEST_TMPDIR/sleep.log"
  : > "$FAKE_SLEEP_LOG"
  cat > "$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == 0.3 ]]; then
  printf '%s\n' "$*" >> "$FAKE_SLEEP_LOG"
  lock="$XDG_RUNTIME_DIR/eww-island/lock"
  if [[ -e $lock ]] && ! flock -n "$lock" true; then
    echo locked >> "$FAKE_SLEEP_LOG"
  fi
  if [[ -n $FAKE_POINTER_AFTER_HOVER_DELAY ]]; then
    echo "$FAKE_POINTER_AFTER_HOVER_DELAY" > "$FAKE_POINTER"
  fi
else
  exec /usr/bin/sleep "$@"
fi
EOF
  chmod +x "$BIN/sleep"
}
wait_for_calls() {
  for _ in {1..100}; do
    [[ $(calls) == "$1" ]] && return 0
    sleep 0.02
  done
  [ "$(calls)" = "$1" ]
}

@test "hover waits 0.3 seconds without a lock and opens when the pointer stays on the island" {
  stub_hover_sleep; on_compact
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$OPEN" ]
  [ "$(cat "$FAKE_SLEEP_LOG")" = 0.3 ]
}

@test "hover never opens when the pointer leaves the island during the 0.3 second delay" {
  stub_hover_sleep; on_compact
  export FAKE_POINTER_AFTER_HOVER_DELAY='960 700'
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
  [ "$(cat "$FAKE_SLEEP_LOG")" = 0.3 ]
}

@test "hover over an open island only reveals it without waiting" {
  stub_hover_sleep; expanded; on_expanded_only
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_reveal=true' ]
  [ ! -s "$FAKE_SLEEP_LOG" ]
}

@test "hover after the pointer left hides, then closes the expanded window" {
  expanded
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$CLOSE" ]
}

@test "a crossing event while the pointer stays on the island (pointer grab) never collapses it" {
  expanded; on_compact
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_reveal=true' ]
}

@test "a stale hover for a pointer that already left never opens the island" {
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "a pointer that left while the window opened collapses it again" {
  on_compact; export FAKE_POINTER_AFTER_OPEN='960 700'
  run "$SCRIPTS/island" hover
  [ "$(calls)" = "$OPEN"$'\n'"$CLOSE" ]
}

@test "hover away keeps the island open until a running auto-expand ends" {
  expanded; auto_running
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "a pointer that comes back while the island is hiding keeps it open" {
  expanded
  "$SCRIPTS/island" hover & pid=$!
  for _ in {1..40}; do grep -qx 'update island_reveal=false' "$FAKE_EWW_LOG" && break; sleep 0.05; done
  on_expanded_only
  wait "$pid"
  [ "$(calls)" = $'update island_reveal=false\nupdate island_reveal=true' ]
}

@test "auto expands, then collapses at its deadline when not hovered" {
  run "$SCRIPTS/island" auto 0
  [ "$status" -eq 0 ]
  wait_for_calls "$OPEN"$'\n'"$CLOSE"
  [ "$(calls)" = "$OPEN"$'\n'"$CLOSE" ]
}

@test "auto never collapses an island the pointer is on" {
  on_compact
  run "$SCRIPTS/island" auto 0
  [ "$(calls)" = "$OPEN" ]
}

@test "close collapses an open island the pointer is not on" {
  expanded
  run "$SCRIPTS/island" close
  [ "$(calls)" = "$CLOSE" ]
}

@test "close keeps an island the pointer is on open (track change while hovering)" {
  expanded; on_expanded_only
  run "$SCRIPTS/island" close
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "close cancels a running auto-expand" {
  expanded; auto_running
  run "$SCRIPTS/island" close
  [ "$(calls)" = "$CLOSE" ]
  [ "$(cat "$ST/auto_until")" = 0 ]
}

@test "close on a collapsed island touches nothing" {
  run "$SCRIPTS/island" close
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
}

@test "concurrent hover calls open the expanded window once" {
  on_compact; export FAKE_EWW_OPEN_DELAY=0.2
  "$SCRIPTS/island" hover & "$SCRIPTS/island" hover & wait
  [ "$(grep -c '^open island-expanded$' "$FAKE_EWW_LOG")" = 1 ]
}

@test "unknown commands and bad durations are rejected without touching eww" {
  run "$SCRIPTS/island" auto soon; [ "$status" -eq 2 ]
  run "$SCRIPTS/island" explode;   [ "$status" -eq 2 ]
  run "$SCRIPTS/island" hover-on;  [ "$status" -eq 2 ]
  [ "$(calls)" = "" ]
}

@test "auto accepts durations with leading zeros" {
  run timeout 1 "$SCRIPTS/island" auto 08
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$OPEN" ]
}
