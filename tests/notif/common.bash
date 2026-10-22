# tests/notif/common.bash: setup and helpers shared by tests/notif/*.bats.
setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" FIX="$BATS_TEST_TMPDIR" EXPECTED_CFG="$REPO/eww"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" XDG_DATA_DIRS="$BATS_TEST_TMPDIR/sysdata"
  export ISLAND_UPTIME_FILE="$BATS_TEST_TMPDIR/uptime" ISLAND_NOTIF_SETTLE_SECONDS=0.05
  export ISLAND_NOTIF_TICK_SECONDS=60
  ST="$XDG_RUNTIME_DIR/eww-island"
  FIFO="$ST/notif.fifo"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$ST"
  # dunst timestamps are CLOCK_BOOTTIME microseconds, the clock behind /proc/uptime.
  NOW=100000
  printf '%s.25 4242.00\n' "$NOW" > "$ISLAND_UPTIME_FILE"
  : > "$FIX/notes"
  write_history
  : > "$FIX/windows"
  printf 'musik\n' > "$FIX/island_tab"
  # Fake dunstctl over $FIX/history.json in the real `dunstctl history` shape.
  cat > "$BIN/dunstctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIX/dunstctl.log"
case $1 in
  history) cat "$FIX/history.json" ;;
  history-rm)
    jq -c --argjson id "$2" '.data[0] |= (. as $a | (first(range($a | length) | select($a[.].id.data == $id)) // null) as $i
      | if $i == null then $a else $a[:$i] + $a[$i + 1:] end)' "$FIX/history.json" > "$FIX/history.tmp"
    mv "$FIX/history.tmp" "$FIX/history.json" ;;
  history-clear) printf '{"type":"aa{sv}","data":[[]]}\n' > "$FIX/history.json" ;;
esac
EOF
  # Fake eww: `get island_tab` answers $FIX/island_tab; everything else is logged.
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FIX/eww.log"; exit 1; fi
if [[ $1 == get && $2 == island_tab ]]; then cat "$FIX/island_tab"; exit 0; fi
printf '%s\n' "$*" >> "$FIX/eww.log"
EOF
  # Fake xdotool: `search` answers the first "CLASS WINDOW" line of $FIX/windows matching the regex.
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIX/xdotool.log"
if [[ $1 == search ]]; then
  shopt -s nocasematch
  pattern=${!#}
  while read -r class window; do
    if [[ $class =~ $pattern ]]; then printf '%s\n' "$window"; exit 0; fi
  done < "$FIX/windows"
  exit 1
fi
EOF
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$FIX/gtk-launch.log"\n' > "$BIN/gtk-launch"
  chmod +x "$BIN/dunstctl" "$BIN/eww" "$BIN/xdotool" "$BIN/gtk-launch"
  export PATH="$BIN:$PATH"
  BELL=$'\U000F009A'
}

teardown() {
  if [[ -n ${listener_pid:-} ]]; then
    kill "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
}

# note ID APP SUMMARY [BODY] [AGE_SECONDS] [ICON] [TAG] [URGENCY]: one history entry, as dunst stores it.
note() {
  jq -cn --argjson id "$1" --arg app "$2" --arg summary "$3" --arg body "${4:-}" \
    --argjson ts "$(( (NOW - ${5:-0}) * 1000000 ))" --arg icon "${6:-}" --arg tag "${7:-}" \
    --arg urgency "${8:-NORMAL}" \
    '{body: {type: "s", data: $body}, message: {type: "s", data: ($summary + "\n" + $body)},
      summary: {type: "s", data: $summary}, appname: {type: "s", data: $app},
      category: {type: "s", data: ""}, default_action_name: {type: "s", data: "default"},
      icon_path: {type: "s", data: $icon}, id: {type: "i", data: $id},
      timestamp: {type: "x", data: $ts}, timeout: {type: "x", data: 5000000},
      progress: {type: "i", data: -1}, urgency: {type: "s", data: $urgency},
      stack_tag: {type: "s", data: $tag}, urls: {type: "s", data: ""}}' >> "$FIX/notes"
}
write_history() { jq -sc '{type: "aa{sv}", data: [.]}' "$FIX/notes" > "$FIX/history.json"; }

start_listener() {
  mkfifo "$FIX/output"
  exec {output_fd}<> "$FIX/output"
  "$SCRIPTS/notif" > "$FIX/output" 2> "$FIX/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" event
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -p $FIFO ]] && break
    sleep 0.01
  done
  [ -p "$FIFO" ]
}

signal() { printf '%s\n' "$1" > "$FIFO"; }
next_event() { IFS= read -r -t "${1:-1}" -u "$output_fd" event; }
quiet() {
  if IFS= read -r -t "$1" -u "$output_fd" event; then
    printf 'unexpected event: %s\n' "$event" >&2
    return 1
  fi
}
ids() { jq -c '[.rows[].id]' <<< "$event"; }
field() { jq -c "[.rows[].$1]" <<< "$event"; }
history_reads() { grep -cx history "$FIX/dunstctl.log" 2>/dev/null || :; }
wait_for_line() {
  local attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -qxF -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.02
  done
  printf 'missing %s in %s\n' "$2" "$1" >&2
  return 1
}
# post ID SUMMARY APP [ENTRY]: run the hook the way dunst does.
post() {
  DUNST_ID=$1 DUNST_SUMMARY=$2 DUNST_BODY='' DUNST_URGENCY=NORMAL DUNST_APP_NAME=$3 DUNST_ICON_PATH='' \
    DUNST_DESKTOP_ENTRY=${4:-} DUNST_STACK_TAG='' "$SCRIPTS/notify-hook" "$3" "$2" '' '' NORMAL
}
