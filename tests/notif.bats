load helpers
bats_require_minimum_version 1.5.0

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

@test "listener starts with dunst history, newest first" {
  note 3 Firefox Unduhan 'selesai' 600
  note 9 Telegram Andi 'halo' 5
  note 5 Thunderbird Rapat 'jam 3' 120
  write_history
  start_listener
  [ "$(jq -c '[.total,.unread,.more,.offset]' <<< "$event")" = '[3,3,0,0]' ]
  [ "$(ids)" = '[9,5,3]' ]
  [ "$(jq -c '.rows[0] | [.app,.summary,.body,.critical]' <<< "$event")" = '["Telegram","Andi","halo",false]' ]
  [ "$(jq -r .label <<< "$event")" = 'Notifikasi 3' ]
}

@test "an empty history, a missing dunstctl or broken output show an empty center" {
  start_listener
  [ "$(jq -c '[.total,.unread,.rows,.more,.label]' <<< "$event")" = '[0,0,[],0,"Notifikasi"]' ]
  kill "$listener_pid"; wait "$listener_pid" 2>/dev/null || :; listener_pid=''; rm -f "$FIX/output"
  printf 'not json\n' > "$FIX/history.json"
  start_listener
  [ "$(jq -c '[.total,.rows]' <<< "$event")" = '[0,[]]' ]
}

@test "the island's own failures and OSD stack tags stay out of the center" {
  note 1 eww-island 'island gagal' x 10 '' '' CRITICAL
  note 2 pactl Volume '' 10 '' obvolume
  note 3 light Kecerahan '' 10 '' obbacklight
  note 4 app Ok '' 10
  write_history
  start_listener
  [ "$(ids)" = '[4]' ]
  [ "$(jq -r .total <<< "$event")" = 1 ]
}

@test "older copies with the same id, or the same app and stack tag, hide behind the newest" {
  note 7 app Unduh '10%' 30
  note 7 app Unduh '60%' 20
  note 10 spotify Lagu a 50 '' now
  note 11 spotify Lagu b 40 '' now
  note 12 other Lagu c 45 '' now
  write_history
  start_listener
  [ "$(ids)" = '[7,11,12]' ]
  [ "$(field body)" = '["60%","b","c"]' ]
}

@test "times are relative to now on dunst's boot clock" {
  note 1 app A '' 0
  note 2 app B '' 59
  note 3 app C '' 300
  note 4 app D '' 7200
  write_history
  start_listener
  [ "$(field time)" = '["baru saja","baru saja","5 mnt","2 jam"]' ]
  : > "$FIX/notes"
  note 5 app E '' $((3 * 86400 + 60))
  note 6 app F '' -30
  write_history
  signal '@refresh'
  next_event
  [ "$(field time)" = '["baru saja","3 hari"]' ]
}

@test "summary and body become plain single-line text" {
  note 1 app '<b>Andi</b> &amp; Budi' $'**Halo**   "kamu"\n<i>baris</i>\t&lt;2&gt;' 10
  write_history
  start_listener
  [ "$(jq -r '.rows[0].summary' <<< "$event")" = 'Andi & Budi' ]
  [ "$(jq -r '.rows[0].body' <<< "$event")" = '**Halo** "kamu" baris <2>' ]
}

@test "an icon file becomes a percent-encoded file URI; otherwise the bell shows" {
  local icon="$BATS_TEST_TMPDIR/icons dir/my icon#1.png"
  mkdir -p "${icon%/*}"; : > "$icon"
  note 1 app Foto '' 20 "$icon"
  note 2 app Lain '' 10 "$BATS_TEST_TMPDIR/missing.png"
  note 3 app Kritis '' 5 '' '' CRITICAL
  write_history
  start_listener
  [ "$(jq -r '.rows[2].image' <<< "$event")" = "file://$(jq -rn --arg p "$icon" '$p | split("/") | map(@uri) | join("/")')" ]
  [ "$(jq -c '[.rows[1].image, .rows[0].image]' <<< "$event")" = '["",""]' ]
  [ "$(jq -r '.rows[1].icon' <<< "$event")" = "$BELL" ]
  [ "$(jq -c '[.rows[].critical]' <<< "$event")" = '[true,false,false]' ]
}

@test "at most four rows show and the rest count as +N" {
  local id
  for id in 1 2 3 4 5 6; do note "$id" app "N$id" '' $((100 - id)); done
  write_history
  start_listener
  [ "$(ids)" = '[6,5,4,3]' ]
  [ "$(jq -c '[.total,.more,.offset]' <<< "$event")" = '[6,2,0]' ]
}

@test "scrolling pages through older notifications and stops at both ends" {
  local id
  for id in 1 2 3 4 5 6; do note "$id" app "N$id" '' $((100 - id)); done
  write_history
  start_listener
  run "$SCRIPTS/notif" scroll down
  [ "$status" -eq 0 ]
  next_event
  [ "$(ids)" = '[5,4,3,2]' ]
  [ "$(jq -c '[.more,.offset]' <<< "$event")" = '[1,1]' ]
  "$SCRIPTS/notif" scroll down
  next_event
  [ "$(ids)" = '[4,3,2,1]' ]
  "$SCRIPTS/notif" scroll down
  quiet 0.2
  "$SCRIPTS/notif" scroll up
  "$SCRIPTS/notif" scroll up
  "$SCRIPTS/notif" scroll up
  next_event; next_event
  [ "$(ids)" = '[6,5,4,3]' ]
  quiet 0.2
}

@test "collapsing the island scrolls the list back to the newest" {
  local id
  for id in 1 2 3 4 5; do note "$id" app "N$id" '' $((100 - id)); done
  write_history
  start_listener
  signal '@expanded 1'
  "$SCRIPTS/notif" scroll down
  next_event
  [ "$(jq -r .offset <<< "$event")" = 1 ]
  signal '@expanded 0'
  next_event
  [ "$(jq -r .offset <<< "$event")" = 0 ]
}

@test "unread counts notifications newer than the last view of the tab" {
  note 1 app Lama '' 600
  note 2 app Baru '' 60
  note 3 app Terbaru '' 10
  write_history
  printf '%s\n' "$(( (NOW - 300) * 1000000 ))" > "$ST/notif_seen"
  start_listener
  [ "$(jq -c '[.total,.unread,.label]' <<< "$event")" = '[3,2,"Notifikasi 2"]' ]
}

@test "opening the island on the notification tab marks everything read and remembers when" {
  note 1 app A '' 60
  write_history
  printf 'notif\n' > "$FIX/island_tab"
  start_listener
  [ "$(jq -r .unread <<< "$event")" = 1 ]
  signal '@expanded 1'
  next_event
  [ "$(jq -c '[.unread,.label]' <<< "$event")" = '[0,"Notifikasi"]' ]
  [ "$(cat "$ST/notif_seen")" = "$(( NOW * 1000000 + 250000 ))" ]
}

@test "the expanded island on another tab leaves notifications unread until the tab is picked" {
  note 1 app A '' 60
  write_history
  start_listener
  signal '@expanded 1'
  quiet 0.2
  [ ! -e "$ST/notif_seen" ]
  printf 'notif\n' > "$FIX/island_tab"
  signal '@tab notif'
  next_event
  [ "$(jq -r .unread <<< "$event")" = 0 ]
}

@test "a notification arriving while the tab is shown counts as read" {
  printf 'notif\n' > "$FIX/island_tab"
  start_listener
  signal '@expanded 1'
  quiet 0.15
  # It arrives after the view started, so only a view that continues makes it read.
  note 4 app Baru '' -2
  write_history
  printf '%s.25 0\n' "$((NOW + 5))" > "$ISLAND_UPTIME_FILE"
  signal '@refresh'
  next_event
  [ "$(jq -c '[.total,.unread]' <<< "$event")" = '[1,0]' ]
}

@test "the hook refreshes the center once dunst has stored the notification" {
  start_listener
  note 21 Telegram Andi halo 0
  write_history
  post 21 Andi Telegram
  next_event
  [ "$(ids)" = '[21]' ]
  [ "$(jq -r .unread <<< "$event")" = 1 ]
}

@test "a burst of new notifications reads the history once" {
  start_listener
  local before
  before=$(history_reads)
  note 1 app A '' 0
  write_history
  signal '@refresh'; signal '@refresh'; signal '@refresh'
  next_event
  quiet 0.2
  [ "$(history_reads)" -eq $((before + 1)) ]
}

@test "repeated expand signals while open never re-read the history" {
  note 1 app A '' 0
  write_history
  start_listener
  signal '@expanded 1'
  sleep 0.2
  local before
  before=$(history_reads)
  signal '@expanded 1'; signal '@expanded 1'
  quiet 0.2
  [ "$(history_reads)" -eq "$before" ]
}

@test "relative times tick only while the island is expanded" {
  export ISLAND_NOTIF_TICK_SECONDS=0.2
  note 1 app A '' 0
  write_history
  start_listener
  printf '%s.25 0\n' "$((NOW + 600))" > "$ISLAND_UPTIME_FILE"
  quiet 0.4
  signal '@expanded 1'
  next_event
  [ "$(field time)" = '["10 mnt"]' ]
  printf '%s.25 0\n' "$((NOW + 7200))" > "$ISLAND_UPTIME_FILE"
  next_event 0.5
  [ "$(field time)" = '["2 jam"]' ]
  signal '@expanded 0'
  sleep 0.1
  printf '%s.25 0\n' "$((NOW + 3 * 86400))" > "$ISLAND_UPTIME_FILE"
  quiet 0.5
}

@test "clicking a row activates its app window and removes it with its hidden copies" {
  printf 'firefox 42\n' > "$FIX/windows"
  note 30 Firefox Unduh '10%' 30 '' dl
  note 31 Firefox Unduh '90%' 20 '' dl
  note 32 app Lain '' 10
  write_history
  start_listener
  [ "$(ids)" = '[32,31]' ]
  run "$SCRIPTS/notif" click 31
  [ "$status" -eq 0 ]
  next_event
  [ "$(ids)" = '[32]' ]
  wait_for_line "$FIX/xdotool.log" 'windowactivate 42'
  grep -qx 'history-rm 31' "$FIX/dunstctl.log"
  grep -qx 'history-rm 30' "$FIX/dunstctl.log"
  [ "$(jq -c '[.data[0][].id.data]' "$FIX/history.json")" = '[32]' ]
}

@test "click finds the window through the desktop entry the hook saw" {
  mkdir -p "$XDG_DATA_DIRS/applications"
  printf '[Desktop Entry]\nName=Telegram\nStartupWMClass=TelegramDesktop\n' \
    > "$XDG_DATA_DIRS/applications/org.telegram.desktop.desktop"
  printf 'TelegramDesktop 77\n' > "$FIX/windows"
  post 31 Andi 'Telegram Desktop' org.telegram.desktop
  note 31 'Telegram Desktop' Andi halo 5
  write_history
  "$SCRIPTS/notif" click 31
  wait_for_line "$FIX/xdotool.log" 'windowactivate 77'
}

@test "click without an app window launches the desktop entry, or only removes without one" {
  post 34 'Unduhan selesai' Files org.gnome.Nautilus
  note 34 Files 'Unduhan selesai' '' 5
  note 35 notify-send 'Skrip selesai' '' 4
  write_history
  "$SCRIPTS/notif" click 34
  wait_for_line "$FIX/gtk-launch.log" org.gnome.Nautilus
  "$SCRIPTS/notif" click 35
  sleep 0.2
  [ "$(cat "$FIX/gtk-launch.log")" = org.gnome.Nautilus ]
  [ "$(jq -c '.data[0]' "$FIX/history.json")" = '[]' ]
  run ! grep -q windowactivate "$FIX/xdotool.log"
}

@test "a desktop entry recorded for another app with a reused id is ignored" {
  post 40 Lama 'Telegram Desktop' org.telegram.desktop
  note 40 Files Baru '' 5
  write_history
  "$SCRIPTS/notif" click 40
  sleep 0.2
  [ ! -e "$FIX/gtk-launch.log" ]
}

@test "a click on a notification no longer in history changes nothing" {
  printf 'app 5\n' > "$FIX/windows"
  note 1 app A '' 5
  write_history
  run "$SCRIPTS/notif" click 99
  [ "$status" -eq 0 ]
  sleep 0.2
  run ! grep -q windowactivate "$FIX/xdotool.log"
  run ! grep -q history-rm "$FIX/dunstctl.log"
  run "$SCRIPTS/notif" click abc
  [ "$status" -eq 2 ]
}

@test "Hapus semua clears dunst history and the center" {
  note 1 app A '' 5
  note 2 app B '' 4
  write_history
  start_listener
  run "$SCRIPTS/notif" clear
  [ "$status" -eq 0 ]
  grep -qx history-clear "$FIX/dunstctl.log"
  next_event
  [ "$(jq -c '[.total,.rows,.label]' <<< "$event")" = '[0,[],"Notifikasi"]' ]
}

@test "commands without a running listener act on dunst and exit quietly" {
  note 1 app A '' 5
  write_history
  run timeout 2 "$SCRIPTS/notif" scroll down
  [ "$status" -eq 0 ]
  run timeout 2 "$SCRIPTS/notif" clear
  [ "$status" -eq 0 ]
  [ ! -e "$FIFO" ]
  run "$SCRIPTS/notif" explode
  [ "$status" -eq 2 ]
}

@test "the hook's desktop-entry record stays bounded" {
  local id
  for id in $(seq 1 80); do post "$id" "N$id" app "org.example.app$id"; done
  [ "$(wc -l < "$ST/notif_entries")" -le 64 ]
  grep -q $'^80\tapp\torg.example.app80$' "$ST/notif_entries"
}

@test "listener exit removes its fifo" {
  start_listener
  kill "$listener_pid"
  wait "$listener_pid" 2>/dev/null || :
  listener_pid=''
  [ ! -e "$FIFO" ]
}
