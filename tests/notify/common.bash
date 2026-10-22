# tests/notify/common.bash: setup and helpers shared by tests/notify/*.bats.
setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" NOTIFY_FIXTURE="$BATS_TEST_TMPDIR"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" XDG_DATA_DIRS="$BATS_TEST_TMPDIR/sysdata"
  export ISLAND_NOTIFY_SECONDS=0.3
  ST="$XDG_RUNTIME_DIR/eww-island"
  FIFO="$ST/notify.fifo"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$ST"
  printf 'false\n' > "$NOTIFY_FIXTURE/paused"
  : > "$NOTIFY_FIXTURE/windows"
  cat > "$BIN/dunstctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_FIXTURE/dunstctl.log"
if [[ $1 == is-paused ]]; then cat "$NOTIFY_FIXTURE/paused"; fi
EOF
  # Fake xdotool: `search` answers the first "CLASS WINDOW" line of $NOTIFY_FIXTURE/windows
  # whose class matches the final (regex) argument, case-insensitively like xdotool.
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_FIXTURE/xdotool.log"
if [[ $1 == search ]]; then
  shopt -s nocasematch
  pattern=${!#}
  while read -r class window; do
    if [[ $class =~ $pattern ]]; then printf '%s\n' "$window"; exit 0; fi
  done < "$NOTIFY_FIXTURE/windows"
  exit 1
fi
EOF
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$NOTIFY_FIXTURE/gtk-launch.log"\n' > "$BIN/gtk-launch"
  chmod +x "$BIN/dunstctl" "$BIN/xdotool" "$BIN/gtk-launch"
  export PATH="$BIN:$PATH"
  CLEAR='{"active":false,"id":0,"app":"","summary":"","body":"","icon":"","image":"","critical":false}'
  BELL=$'\U000F009A'
}

teardown() {
  if [[ -n ${listener_pid:-} ]]; then
    kill "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
}

start_listener() {
  mkfifo "$NOTIFY_FIXTURE/output"
  exec {output_fd}<> "$NOTIFY_FIXTURE/output"
  "$SCRIPTS/notify" > "$NOTIFY_FIXTURE/output" 2> "$NOTIFY_FIXTURE/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" first
  [ "$first" = "$CLEAR" ]
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -p $FIFO ]] && break
    sleep 0.01
  done
  [ -p "$FIFO" ]
}

# post ID SUMMARY [BODY] [URGENCY] [APP] [ICON] [ENTRY] [TAG]: run the hook the way dunst does.
post() {
  DUNST_ID=$1 DUNST_SUMMARY=$2 DUNST_BODY=${3:-} DUNST_URGENCY=${4:-NORMAL} DUNST_APP_NAME=${5:-app} \
    DUNST_ICON_PATH=${6:-} DUNST_DESKTOP_ENTRY=${7:-} DUNST_STACK_TAG=${8:-} \
    DUNST_CATEGORY='' DUNST_PROGRESS=-1 DUNST_URLS='' DUNST_TIMEOUT=5000 DUNST_TIMESTAMP=1 \
    "$SCRIPTS/notify-hook" "${5:-app}" "$2" "${3:-}" "${6:-}" "${4:-NORMAL}"
}

signal() { printf '%s\n' "$1" > "$FIFO"; }
next_event() { IFS= read -r -t "${1:-1}" -u "$output_fd" event; }
# quiet SECONDS: fail when the listener prints anything within SECONDS.
quiet() {
  if IFS= read -r -t "$1" -u "$output_fd" event; then
    printf 'unexpected event: %s\n' "$event" >&2
    return 1
  fi
}
summary() { jq -r .summary <<< "$event"; }
wait_for_line() {
  local attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    grep -qxF -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.02
  done
  printf 'missing %s in %s\n' "$2" "$1" >&2
  return 1
}
