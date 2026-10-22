# tests/shortcuts.bats
bats_require_minimum_version 1.5.0

setup() {
  load helpers
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" EXPECTED_CFG="$REPO/eww"
  export FAKE_EWW_LOG="$BATS_TEST_TMPDIR/eww.log" FAKE_EWW_ACTIVE="$BATS_TEST_TMPDIR/active"
  export ISLAND_SHORTCUTS="$BATS_TEST_TMPDIR/shortcuts" FAKE_DIR="$BATS_TEST_TMPDIR"
  ST="$XDG_RUNTIME_DIR/eww-island"; mkdir -p "$ST"
  : > "$FAKE_EWW_LOG"; printf 'island: island\n' > "$FAKE_EWW_ACTIVE"
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FAKE_EWW_LOG"; exit 1; fi
case $1 in
  get) exit 0 ;;
  active-windows) cat "$FAKE_EWW_ACTIVE"; exit 0 ;;
  close) grep -vx "$2: $2" "$FAKE_EWW_ACTIVE" > "$FAKE_EWW_ACTIVE.tmp"; mv "$FAKE_EWW_ACTIVE.tmp" "$FAKE_EWW_ACTIVE" ;;
esac
printf '%s\n' "$*" >> "$FAKE_EWW_LOG"
EOF
  # The pointer sits on the card: a shortcut click must still close it.
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
case $1 in
  getmouselocation) printf 'X=1160\nY=150\nSCREEN=0\nWINDOW=1\n' ;;
  search) printf 'WINDOW=3\nX=706\nY=0\nWIDTH=508\nHEIGHT=218\nSCREEN=0\n' ;;
esac
EOF
  # A stand-in for a screenshot tool: logs its arguments, its session and the open card.
  cat > "$BIN/fakeshot" <<'EOF'
#!/usr/bin/env bash
printf 'launched%s\n' "$(printf ' [%s]' "$@")" >> "$FAKE_EWW_LOG"
ps -o sid= -p $$ | tr -d ' ' > "$FAKE_DIR/sid"
cp "$FAKE_EWW_ACTIVE" "$FAKE_DIR/active_at_launch"
echo LEAK; echo LEAK >&2
if [[ -n ${FAKE_HOLD:-} ]]; then exec sleep "$FAKE_HOLD"; fi
EOF
  cat > "$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send%s\n' "$(printf ' [%s]' "$@")" >> "$FAKE_EWW_LOG"
EOF
  chmod +x "$BIN"/*
  PATH="$BIN:$PATH"
  CLOSE=$'update island_reveal=false\nclose island-expanded'
}
calls() { cat "$FAKE_EWW_LOG"; }
expanded() { printf 'island: island\nisland-expanded: island-expanded\n' > "$FAKE_EWW_ACTIVE"; }
config() { printf '%s\n' "$@" > "$ISLAND_SHORTCUTS"; }
wait_for_log() {
  for _ in {1..100}; do grep -q -- "$1" "$FAKE_EWW_LOG" && return 0; sleep 0.02; done
  grep -q -- "$1" "$FAKE_EWW_LOG"
}

@test "list groups the shortcuts into rows of three with their ids" {
  config 'a | Satu | true' 'b | Dua | true' 'c | Tiga | true' 'd | Empat | true'
  run "$SCRIPTS/shortcuts" list
  [ "$status" -eq 0 ]
  [ "$output" = '[[{"id":0,"icon":"a","label":"Satu","state":""},{"id":1,"icon":"b","label":"Dua","state":""},{"id":2,"icon":"c","label":"Tiga","state":""}],[{"id":3,"icon":"d","label":"Empat","state":""}]]' ]
}

@test "list skips comments and blank lines and trims the fields" {
  config '# Ikon | Label | Perintah' '' '   ' '  # indented comment' '  b  |  Dua kata  |  true --x  '
  run --separate-stderr "$SCRIPTS/shortcuts" list
  [ "$status" -eq 0 ]
  [ "$output" = '[[{"id":0,"icon":"b","label":"Dua kata","state":""}]]' ]
  [ "$stderr" = "" ]
}

@test "list reads the optional state field" {
  config 'c | Jangan ganggu | dunstctl set-paused toggle | dnd'
  run "$SCRIPTS/shortcuts" list
  [ "$output" = '[[{"id":0,"icon":"c","label":"Jangan ganggu","state":"dnd"}]]' ]
}

@test "list skips bad lines with a warning naming the line" {
  config 'a | Satu | true' 'rusak tanpa kolom' 'd |  | true' 'e | Lima |  ' ' | Enam | true' \
    'f | Tujuh | true | wifi' 'g | Delapan | true | dnd | lagi' 'h | Sembilan | true'
  run --separate-stderr "$SCRIPTS/shortcuts" list
  [ "$status" -eq 0 ]
  [ "$output" = '[[{"id":0,"icon":"a","label":"Satu","state":""},{"id":1,"icon":"h","label":"Sembilan","state":""}]]' ]
  for n in 2 3 4 5 6 7; do [[ $stderr == *"baris $n"* ]]; done
  [[ $stderr != *"baris 1"* && $stderr != *"baris 8"* ]]
}

@test "list accepts CRLF line ends and a last line without newline" {
  printf 'a | Satu | true\r\nb | Dua | true' > "$ISLAND_SHORTCUTS"
  run "$SCRIPTS/shortcuts" list
  [ "$output" = '[[{"id":0,"icon":"a","label":"Satu","state":""},{"id":1,"icon":"b","label":"Dua","state":""}]]' ]
}

@test "list escapes labels as JSON" {
  config 'a | Kata "kutip" \ miring | true'
  run "$SCRIPTS/shortcuts" list
  [ "$(jq -r '.[0][0].label' <<< "$output")" = 'Kata "kutip" \ miring' ]
}

@test "list without a config file is empty" {
  run --separate-stderr "$SCRIPTS/shortcuts" list
  [ "$status" -eq 0 ]
  [ "$output" = '[]' ]
}

@test "the shipped config parses without warnings" {
  unset ISLAND_SHORTCUTS
  run --separate-stderr "$SCRIPTS/shortcuts" list
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  [ "$(jq '[.[][]] | length' <<< "$output")" -gt 0 ]
}

@test "watch prints the list again when the config changes" {
  command -v inotifywait >/dev/null || skip "inotifywait missing"
  config 'a | Satu | true'
  coproc WATCH { exec "$SCRIPTS/shortcuts" watch 2>/dev/null 3>&-; }
  IFS= read -r -t 3 -u "${WATCH[0]}" line
  [ "$line" = '[[{"id":0,"icon":"a","label":"Satu","state":""}]]' ]
  sleep 0.2
  config 'b | Dua | true'
  IFS= read -r -t 3 -u "${WATCH[0]}" line
  kill "$WATCH_PID"; wait "$WATCH_PID" || :
  [ "$line" = '[[{"id":0,"icon":"b","label":"Dua","state":""}]]' ]
}

@test "run closes the card first, then launches the command with its arguments" {
  expanded
  config 'a | Screenshot | fakeshot --area "dua kata"'
  run "$SCRIPTS/shortcuts" run 0
  [ "$status" -eq 0 ]
  wait_for_log launched
  [ "$(calls)" = "$CLOSE"$'\nlaunched [--area] [dua kata]' ]
  [ "$(cat "$FAKE_DIR/active_at_launch")" = 'island: island' ]
}

@test "run launches detached: it returns at once, in another session, with no output" {
  expanded
  config 'a | Kunci | fakeshot'
  export FAKE_HOLD=3
  run timeout 2 "$SCRIPTS/shortcuts" run 0
  [ "$status" -eq 0 ]
  [[ $output != *LEAK* ]]
  wait_for_log launched
  [ "$(cat "$FAKE_DIR/sid")" != "$(ps -o sid= -p $$ | tr -d ' ')" ]
}

@test "run counts ids over valid shortcuts only" {
  config '# komentar' 'rusak' 'a | Satu | fakeshot satu' 'b | Dua | fakeshot dua'
  run "$SCRIPTS/shortcuts" run 1
  [ "$status" -eq 0 ]
  wait_for_log launched
  [ "$(calls)" = 'launched [dua]' ]
}

@test "run with a missing program closes the card and says so instead of crashing" {
  expanded
  config 'a | Bluetooth | island-no-such-tool --menu'
  run -127 "$SCRIPTS/shortcuts" run 0
  wait_for_log notify-send
  [[ $(calls) == "$CLOSE"$'\nnotify-send '*island-no-such-tool* ]]
  [[ $(calls) != *launched* ]]
}

@test "run rejects an unknown id without touching the card" {
  expanded
  config 'a | Satu | fakeshot'
  run "$SCRIPTS/shortcuts" run 5
  [ "$status" -eq 2 ]
  run "$SCRIPTS/shortcuts" run satu
  [ "$status" -eq 2 ]
  sleep 0.1
  [ "$(calls)" = "" ]
}

@test "unknown commands are rejected" {
  run "$SCRIPTS/shortcuts" explode
  [ "$status" -eq 2 ]
  run "$SCRIPTS/shortcuts"
  [ "$status" -eq 2 ]
}
