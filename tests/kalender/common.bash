# tests/kalender/common.bash: setup and helpers shared by tests/kalender/*.bats.
setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" FIX="$BATS_TEST_TMPDIR"
  export EXPECTED_CFG="$REPO/eww" ISLAND_KALENDER_TICK=0.2
  ST="$XDG_RUNTIME_DIR/eww-island"
  FIFO="$ST/kalender.fifo"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$ST"
  : > "$FIX/calls"
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FIX/calls"; exit 1; fi
case $1 in
  active-windows) printf 'island: island\nisland-expanded: island-expanded\n'; exit 0 ;;
  get) exit 0 ;;
esac
printf 'eww %s\n' "$*" >> "$FIX/calls"
EOF
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
[[ $1 == getmouselocation ]] && printf 'X=960\nY=900\nSCREEN=0\nWINDOW=1\n'
exit 0
EOF
  cat > "$BIN/xdg-open" <<'EOF'
#!/usr/bin/env bash
printf 'xdg-open %s\n' "$*" >> "$FIX/calls"
EOF
  chmod +x "$BIN/eww" "$BIN/xdotool" "$BIN/xdg-open"
  export PATH="$BIN:$PATH"
}

teardown() {
  if [[ -n ${listener_pid:-} ]]; then
    kill "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
}

start_listener() {
  [[ -p $FIX/output ]] || mkfifo "$FIX/output"
  exec {output_fd}<> "$FIX/output"
  "$SCRIPTS/kalender" > "$FIX/output" 2> "$FIX/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" event
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -p $FIFO ]] && break
    sleep 0.01
  done
  [ -p "$FIFO" ]
}
stop_listener() { kill "$listener_pid"; wait "$listener_pid" 2>/dev/null || :; listener_pid=''; }

kalender() { "$SCRIPTS/kalender" "$@"; }
signal() { printf '%s\n' "$1" > "$FIFO"; }
next_event() { IFS= read -r -t "${1:-1}" -u "$output_fd" event; }
quiet() {
  if IFS= read -r -t "$1" -u "$output_fd" event; then
    printf 'unexpected event: %s\n' "$event" >&2
    return 1
  fi
}
titles() { jq -c '[.rows[].title]' <<< "$event"; }
wait_for_call() { for _ in {1..100}; do grep -q -- "$1" "$FIX/calls" && return 0; sleep 0.02; done; grep -q -- "$1" "$FIX/calls"; }

# agenda STATE...: agenda.json with rows r1..rN in those states (past|now|soon|later).
agenda() {
  jq -nc --arg states "$*" '{ok: true, stale: false, updated: "09:55", error: "", label: "Kalender 2",
    remaining: 2, allday: ["Cuti Bersama", "Konferensi"], next: null, errors: [],
    rows: [$states | split(" ") | to_entries[] | {id: ("00000000000" + (.key + 1 | tostring)),
      start: 0, end: 0, title: ("r" + (.key + 1 | tostring)), account: "Kantor", color: "#4f8cff",
      join: "https://meet.google.com/abc-defg-hij", day: "Hari ini", time: "10:00–10:30", state: .value}]}' \
    > "$ST/agenda.json.new"
  mv "$ST/agenda.json.new" "$ST/agenda.json"
}
# edit_agenda FILTER: apply a jq filter to agenda.json atomically.
edit_agenda() { jq -c "$1" "$ST/agenda.json" > "$ST/agenda.json.new" && mv "$ST/agenda.json.new" "$ST/agenda.json"; }
