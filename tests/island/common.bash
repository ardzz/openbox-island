# tests/island/common.bash: fake eww, xdotool pointer and tab fixtures for scripts/island.
setup() {
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" EXPECTED_CFG="$REPO/eww"
  export FAKE_EWW_LOG="$BATS_TEST_TMPDIR/eww.log" FAKE_EWW_ACTIVE="$BATS_TEST_TMPDIR/active"
  export FAKE_POINTER="$BATS_TEST_TMPDIR/pointer" FAKE_WEATHER="$BATS_TEST_TMPDIR/weather"
  # No shortcuts config unless a test writes one.
  export ISLAND_SHORTCUTS="$BATS_TEST_TMPDIR/shortcuts"
  ST="$XDG_RUNTIME_DIR/eww-island"
  : > "$FAKE_EWW_LOG"; printf 'island: island\n' > "$FAKE_EWW_ACTIVE"; away
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FAKE_EWW_LOG"; exit 1; fi
case $1 in
  get) [[ $2 == weather ]] && cat "$FAKE_WEATHER" 2>/dev/null; exit 0 ;;
  active-windows) cat "$FAKE_EWW_ACTIVE"; exit 0 ;;
  open) sleep "${FAKE_EWW_OPEN_DELAY:-0}"; printf '%s: %s\n' "$2" "$2" >> "$FAKE_EWW_ACTIVE"
        if [[ -n $FAKE_POINTER_AFTER_OPEN ]]; then echo "$FAKE_POINTER_AFTER_OPEN" > "$FAKE_POINTER"; fi ;;
  close) grep -vx "$2: $2" "$FAKE_EWW_ACTIVE" > "$FAKE_EWW_ACTIVE.tmp"; mv "$FAKE_EWW_ACTIVE.tmp" "$FAKE_EWW_ACTIVE" ;;
esac
printf '%s\n' "$*" >> "$FAKE_EWW_LOG"
EOF
  # Fake xdotool: the pointer comes from $FAKE_POINTER; the visible island windows from eww's
  # active windows, at their real geometry on a 1920px screen (compact 508x44+706+0, expanded 508x218+706+0).
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "getmouselocation --shell")
    read -r x y < "$FAKE_POINTER"; printf 'X=%s\nY=%s\nSCREEN=0\nWINDOW=1\n' "$x" "$y" ;;
  "search --onlyvisible --name ^Eww - island(-expanded)?\$ getwindowgeometry --shell %@")
    grep -qx 'island: island' "$FAKE_EWW_ACTIVE" && printf 'WINDOW=2\nX=706\nY=0\nWIDTH=508\nHEIGHT=44\nSCREEN=0\n'
    grep -qx 'island-expanded: island-expanded' "$FAKE_EWW_ACTIVE" && printf 'WINDOW=3\nX=706\nY=0\nWIDTH=508\nHEIGHT=218\nSCREEN=0\n'
    exit 0 ;;
  *) echo "unexpected xdotool $*" >> "$FAKE_EWW_LOG"; exit 1 ;;
esac
EOF
  chmod +x "$BIN/eww" "$BIN/xdotool"
  PATH="$BIN:$PATH"
  OPEN=$'update island_reveal=false island_tab=musik\nopen island-expanded\nupdate island_reveal=true'
  CLOSE=$'update island_reveal=false\nclose island-expanded'
}
calls() { cat "$FAKE_EWW_LOG"; }
expanded() { printf 'island: island\nisland-expanded: island-expanded\n' > "$FAKE_EWW_ACTIVE"; }
on_compact() { echo '960 26' > "$FAKE_POINTER"; }
on_expanded_only() { echo '1160 150' > "$FAKE_POINTER"; }
away() { echo '960 700' > "$FAKE_POINTER"; }
auto_running() { mkdir -p "$ST"; echo $(( $(date +%s) + 60 )) > "$ST/auto_until"; }
# Tab availability: music from the media state file, weather from eww's weather variable.
music() { mkdir -p "$ST"; echo '{"state":"playing","title":"Lagu"}' > "$ST/media.json"; }
no_music() { mkdir -p "$ST"; echo '{"state":"none","title":""}' > "$ST/media.json"; }
weather() { echo '{"ok":true}' > "$FAKE_WEATHER"; }
saved() { mkdir -p "$ST"; echo "$1" > "$ST/tab"; }
shortcuts() { printf 'x | Kunci | true\n' > "$ISLAND_SHORTCUTS"; }
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
