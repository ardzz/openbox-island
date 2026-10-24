# tests/upcoming/common.bash: setup and helpers shared by tests/upcoming/*.bats.
# The clock is pinned to Wed 2026-10-21 10:00 WIB.
setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" FIX="$BATS_TEST_TMPDIR"
  export TZ=Asia/Jakarta ISLAND_NOW=1792551600 ISLAND_UPCOMING_TICK=0.2
  ST="$XDG_RUNTIME_DIR/eww-island"
  DATA="$XDG_DATA_HOME/eww-island/todo.json"
  mkdir -p "$ST" "${DATA%/*}"
}

teardown() { stop_listener; }

# at HH:MM [DAYS]: the epoch of HH:MM WIB on the pinned day, DAYS days later.
at() { local h=${1%:*} m=${1#*:}; printf '%s' $(( 1792515600 + 10#$h * 3600 + 10#$m * 60 + ${2:-0} * 86400 )); }

# row ID START END TITLE [JOIN] [DAY]: one agenda row, today unless DAY is given.
row() {
  jq -nc --arg id "$1" --argjson start "$2" --argjson end "$3" --arg title "$4" --arg join "${5:-}" \
    --arg day "${6:-Hari ini}" '{id: $id, start: $start, end: $end, title: $title, account: "Kantor",
      color: "#4f8cff", join: $join, day: $day, time: "", state: "later"}'
}
# agenda ROW...: an ok agenda.json holding these rows, replaced atomically.
agenda() {
  printf '%s\n' "$@" | jq -sc '{ok: true, stale: false, updated: "09:55", error: "", label: "Kalender",
    remaining: 0, allday: [], next: null, rows: ., errors: []}' > "$ST/agenda.json.new"
  mv "$ST/agenda.json.new" "$ST/agenda.json"
}
# item ID TEXT [DUE] [DONE]: one Tugas item; DUE null = no deadline.
item() {
  jq -nc --argjson id "$1" --arg text "$2" --argjson due "${3:-null}" --argjson done "${4:-false}" \
    '{id: $id, text: $text, done: $done, created: 0} + (if $due == null then {} else {due: $due, reminded: []} end)'
}
# todos ITEM...: the Tugas list holding these items, replaced atomically.
todos() {
  printf '%s\n' "$@" | jq -sc '{next_id: 100, items: .}' > "$DATA.new"
  mv "$DATA.new" "$DATA"
}

start_listener() {
  [[ -p $FIX/output ]] || mkfifo "$FIX/output"
  exec {output_fd}<> "$FIX/output"
  "$SCRIPTS/upcoming" > "$FIX/output" 2> "$FIX/stderr" &
  listener_pid=$!
  next_event 2
}
stop_listener() {
  if [[ -n ${listener_pid:-} ]]; then
    kill "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
    listener_pid=''
  fi
}
next_event() { event=''; IFS= read -r -t "${1:-1}" -u "$output_fd" event; }
# shown: the first line a fresh listener prints for the files as they are now.
shown() { start_listener; stop_listener; }
m() { jq -r ".meeting.$1" <<< "$event"; }
d() { jq -r ".deadline.$1" <<< "$event"; }
