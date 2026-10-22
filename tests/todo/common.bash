# tests/todo/common.bash: setup and helpers shared by tests/todo/*.bats.
setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" FIX="$BATS_TEST_TMPDIR"
  export EXPECTED_CFG="$REPO/eww"
  ST="$XDG_RUNTIME_DIR/eww-island"
  FIFO="$ST/todo.fifo"
  DATA="$XDG_DATA_HOME/eww-island/todo.json"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$ST"
  : > "$FIX/calls"
  # Fake eww and xdotool: every call is logged; the expanded card counts as open, the pointer as away.
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
  # Fake rofi: logs its arguments and menu, answers the next line of $FIX/rofi_answers, cancels when none is left.
  cat > "$BIN/rofi" <<'EOF'
#!/usr/bin/env bash
printf 'rofi %s\n' "$*" >> "$FIX/calls"
menu=$(cat)
[[ -z $menu ]] || printf 'menu %s\n' "${menu//$'\n'/|}" >> "$FIX/calls"
[[ -s $FIX/rofi_answers ]] || exit 1
head -n 1 "$FIX/rofi_answers"
sed -i 1d "$FIX/rofi_answers"
EOF
  cat > "$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send%s\n' "$(printf ' [%s]' "$@")" >> "$FIX/calls"
EOF
  chmod +x "$BIN/eww" "$BIN/xdotool" "$BIN/rofi" "$BIN/notify-send"
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
  "$SCRIPTS/todo" > "$FIX/output" 2> "$FIX/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" event
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -p $FIFO ]] && break
    sleep 0.01
  done
  [ -p "$FIFO" ]
}
stop_listener() { kill "$listener_pid"; wait "$listener_pid" 2>/dev/null || :; listener_pid=''; }

todo() { "$SCRIPTS/todo" "$@"; }
signal() { printf '%s\n' "$1" > "$FIFO"; }
next_event() { IFS= read -r -t "${1:-1}" -u "$output_fd" event; }
quiet() {
  if IFS= read -r -t "$1" -u "$output_fd" event; then
    printf 'unexpected event: %s\n' "$event" >&2
    return 1
  fi
}
texts() { jq -c '[.rows[].text]' <<< "$event"; }
done_flags() { jq -c '[.rows[].done]' <<< "$event"; }
id_of() { jq -r --arg t "$1" '.rows[] | select(.text == $t) | .id' <<< "$event"; }
# add_all TEXT...: add each, oldest first, without a listener.
add_all() { local t; for t in "$@"; do todo add "$t"; done; }
