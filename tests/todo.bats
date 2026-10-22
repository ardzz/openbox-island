load helpers
bats_require_minimum_version 1.5.0

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
  # Fake rofi: logs its arguments and answers $FIX/rofi_answer, or cancels when it is missing.
  cat > "$BIN/rofi" <<'EOF'
#!/usr/bin/env bash
printf 'rofi %s\n' "$*" >> "$FIX/calls"
[[ -f $FIX/rofi_answer ]] || exit 1
cat "$FIX/rofi_answer"
EOF
  chmod +x "$BIN/eww" "$BIN/xdotool" "$BIN/rofi"
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

@test "a missing list shows an empty tab labelled Tugas" {
  start_listener
  [ "$(jq -c '[.open,.label,.rows,.more,.offset]' <<< "$event")" = '[0,"Tugas",[],0,0]' ]
}

@test "add stores trimmed text in the data dir and the label counts open items" {
  start_listener
  run todo add '   beli susu  '
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["beli susu"]' ]
  [ "$(done_flags)" = '[false]' ]
  [ "$(jq -c '[.open,.label]' <<< "$event")" = '[1,"Tugas 1"]' ]
  [ -s "$DATA" ]
}

@test "add flattens line breaks and tabs into single spaces" {
  todo add $'bayar\n\tlistrik   dan  air'
  start_listener
  [ "$(texts)" = '["bayar listrik dan air"]' ]
}

@test "add rejects empty or whitespace-only text and leaves the list alone" {
  todo add satu
  run todo add ''
  [ "$status" -ne 0 ]
  run todo add $'   \n\t '
  [ "$status" -ne 0 ]
  run todo add
  [ "$status" -ne 0 ]
  start_listener
  [ "$(texts)" = '["satu"]' ]
}

@test "open items come first, newest first; done items follow, latest finished first" {
  add_all a b c d
  start_listener
  [ "$(texts)" = '["d","c","b","a"]' ]
  todo toggle "$(id_of a)"; next_event
  todo toggle "$(id_of c)"; next_event
  [ "$(texts)" = '["d","b","c","a"]' ]
  [ "$(done_flags)" = '[false,false,true,true]' ]
  [ "$(jq -r .label <<< "$event")" = 'Tugas 2' ]
}

@test "toggling a done item reopens it in its place among the open ones" {
  add_all a b c
  start_listener
  todo toggle "$(id_of b)"; next_event
  [ "$(texts)" = '["c","a","b"]' ]
  todo toggle "$(id_of b)"; next_event
  [ "$(texts)" = '["c","b","a"]' ]
  [ "$(jq -c '[.open,.label]' <<< "$event")" = '[3,"Tugas 3"]' ]
}

@test "the label drops the count once everything is done" {
  todo add a
  start_listener
  todo toggle "$(id_of a)"; next_event
  [ "$(jq -c '[.open,.label]' <<< "$event")" = '[0,"Tugas"]' ]
}

@test "remove deletes one item by id" {
  add_all a b c
  start_listener
  run todo remove "$(id_of b)"
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["c","a"]' ]
}

@test "unknown ids change nothing and malformed ids are usage errors" {
  add_all a
  start_listener
  run todo toggle 999
  [ "$status" -eq 1 ]
  run todo remove 999
  [ "$status" -eq 1 ]
  run todo toggle abc
  [ "$status" -eq 2 ]
  run todo remove ''
  [ "$status" -eq 2 ]
  quiet 0.3
  stop_listener; start_listener
  [ "$(texts)" = '["a"]' ]
  [ "$(done_flags)" = '[false]' ]
}

@test "ids are never reused after a removal" {
  add_all a b
  start_listener
  local old
  old=$(id_of b)
  todo remove "$old"; next_event
  todo add c; next_event
  [ "$(id_of c)" != "$old" ]
}

@test "clear-done removes only finished items" {
  add_all a b c
  start_listener
  todo toggle "$(id_of a)"; next_event
  todo toggle "$(id_of c)"; next_event
  run todo clear-done
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["b"]' ]
}

@test "the list survives a listener restart and is read from the data file" {
  add_all a b
  start_listener
  todo toggle "$(id_of a)"; next_event
  stop_listener
  start_listener
  [ "$(texts)" = '["b","a"]' ]
  [ "$(done_flags)" = '[false,true]' ]
}

@test "a corrupt list reads as empty and is kept aside on the next write" {
  mkdir -p "${DATA%/*}"
  printf 'not json\n' > "$DATA"
  start_listener
  [ "$(jq -c '[.open,.rows]' <<< "$event")" = '[0,[]]' ]
  todo add baru
  next_event
  [ "$(texts)" = '["baru"]' ]
  [ "$(cat "$DATA.corrupt")" = 'not json' ]
}

@test "concurrent adds all land with distinct ids and leave no temp files" {
  local i
  for i in 1 2 3 4 5 6 7 8; do todo add "t$i" & done
  wait
  start_listener
  [ "$(jq '.rows | length' <<< "$event")" -eq 4 ]
  [ "$(jq .open <<< "$event")" -eq 8 ]
  [ "$(jq '.more' <<< "$event")" -eq 4 ]
  [ "$(ls -A "${DATA%/*}" | grep -cv '^todo\.json\(\.lock\)\?$')" -eq 0 ]
  [ "$(jq '[.rows[].id] | unique | length' <<< "$event")" -eq 4 ]
  # Distinct ids: finishing the four shown rows leaves exactly four open.
  local id
  for id in $(jq -r '.rows[].id' <<< "$event"); do todo toggle "$id"; next_event; done
  [ "$(jq .open <<< "$event")" -eq 4 ]
}

@test "at most four rows show and the rest count as +N" {
  add_all 1 2 3 4 5 6
  start_listener
  [ "$(texts)" = '["6","5","4","3"]' ]
  [ "$(jq -c '[.more,.offset]' <<< "$event")" = '[2,0]' ]
}

@test "scrolling pages through the rows and stops at both ends" {
  add_all 1 2 3 4 5 6
  start_listener
  todo scroll down; next_event
  [ "$(texts)" = '["5","4","3","2"]' ]
  [ "$(jq -c '[.more,.offset]' <<< "$event")" = '[1,1]' ]
  todo scroll down; next_event
  [ "$(texts)" = '["4","3","2","1"]' ]
  todo scroll down
  quiet 0.3
  todo scroll up; next_event
  todo scroll up; next_event
  [ "$(jq .offset <<< "$event")" -eq 0 ]
  todo scroll up
  quiet 0.3
}

@test "a short list never scrolls" {
  add_all 1 2 3
  start_listener
  todo scroll down
  quiet 0.3
}

@test "removing items pulls the scroll offset back into range" {
  add_all 1 2 3 4 5 6
  start_listener
  todo scroll down; next_event
  todo scroll down; next_event
  todo remove "$(id_of 1)"; next_event
  [ "$(jq -c '[.offset,.more]' <<< "$event")" = '[1,0]' ]
  [ "$(texts)" = '["5","4","3","2"]' ]
}

@test "collapsing the island scrolls the list back to the top" {
  add_all 1 2 3 4 5
  start_listener
  todo scroll down; next_event
  signal '@expanded 0'
  next_event
  [ "$(jq .offset <<< "$event")" -eq 0 ]
}

@test "the listener emits once after every command and idles otherwise" {
  start_listener
  todo add a; next_event
  [ "$(texts)" = '["a"]' ]
  todo toggle "$(id_of a)"; next_event
  [ "$(done_flags)" = '[true]' ]
  todo toggle "$(id_of a)"; next_event
  [ "$(done_flags)" = '[false]' ]
  todo toggle "$(id_of a)"; next_event
  todo clear-done; next_event
  [ "$(texts)" = '[]' ]
  todo add b; next_event
  todo remove "$(id_of b)"; next_event
  [ "$(texts)" = '[]' ]
  quiet 0.5
}

@test "commands work while no listener runs" {
  run todo add a
  [ "$status" -eq 0 ]
  [ ! -e "$FIFO" ]
  start_listener
  [ "$(texts)" = '["a"]' ]
}

@test "prompt closes the card, asks rofi and adds the answer" {
  printf '  telepon ibu \n' > "$FIX/rofi_answer"
  start_listener
  run todo prompt
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["telepon ibu"]' ]
  grep -q '^rofi .*-dmenu' "$FIX/calls"
  grep -q '^rofi .*-p Tugas' "$FIX/calls"
  # The card is closed before rofi asks.
  [ "$(grep -nm1 'close island-expanded' "$FIX/calls" | cut -d: -f1)" -lt "$(grep -nm1 '^rofi' "$FIX/calls" | cut -d: -f1)" ]
}

@test "cancelling the prompt adds nothing" {
  start_listener
  run todo prompt
  [ "$status" -eq 0 ]
  quiet 0.3
  [ ! -e "$DATA" ] || [ "$(jq -c '[.rows]' <<< "$event")" = '[[]]' ]
}

@test "unknown commands and scroll directions are usage errors" {
  run todo explode
  [ "$status" -eq 2 ]
  run todo scroll left
  [ "$status" -eq 2 ]
  [ ! -e "$DATA" ]
}
