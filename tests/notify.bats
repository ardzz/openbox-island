load helpers
bats_require_minimum_version 1.5.0

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

@test "hook writes one JSON line per notification to the listener fifo" {
  mkfifo "$FIFO"
  exec {reader}<> "$FIFO"
  post 571 'Rapat' 'Mulai sebentar lagi' CRITICAL Thunderbird /usr/share/icons/x.png org.mozilla.thunderbird tagz
  IFS= read -r -t 1 -u "$reader" line
  [ "$(jq -c '[.id,.app,.summary,.body,.icon,.urgency,.entry,.tag]' <<< "$line")" = '[571,"Thunderbird","Rapat","Mulai sebentar lagi","/usr/share/icons/x.png","CRITICAL","org.mozilla.thunderbird","tagz"]' ]
}

@test "hook flattens control characters and truncates fields to one atomic pipe write" {
  mkfifo "$FIFO"
  exec {reader}<> "$FIFO"
  local body summary
  printf -v body '%.0s"é\\\t\n' {1..3000}
  printf -v summary '%.0s<b>' {1..1000}
  post 9 "$summary" "$body" NORMAL "$summary" "/icons/$body" "$summary" "$summary"
  IFS= read -r -t 1 -u "$reader" line
  if IFS= read -r -t 0.05 -u "$reader" extra; then false; fi
  jq -e . <<< "$line" > /dev/null
  [ "$(LC_ALL=C; printf '%s' "${#line}")" -lt 4096 ]
  [ "$(jq -r '.body | test("[\n\t]")' <<< "$line")" = false ]
  [[ $(jq -r .body <<< "$line") == '"é\  "é\'* ]]
}

@test "hook exits quietly without a running listener" {
  run timeout 2 env DUNST_ID=1 DUNST_SUMMARY=x "$SCRIPTS/notify-hook"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$FIFO" ]
}

@test "hook never blocks on a fifo nobody reads" {
  mkfifo "$FIFO"
  run timeout 2 env DUNST_ID=1 DUNST_SUMMARY=x "$SCRIPTS/notify-hook"
  [ "$status" -eq 0 ]
}

@test "listener starts cleared, shows a notification for its hold, then clears" {
  start_listener
  quiet 0.05
  post 41 'Rapat' 'Mulai 5 menit lagi'
  next_event
  [ "$(jq -c '[.active,.id,.app,.summary,.body,.image,.critical]' <<< "$event")" = '[true,41,"app","Rapat","Mulai 5 menit lagi","",false]' ]
  [ "$(jq -r .icon <<< "$event")" = "$BELL" ]
  quiet 0.2
  next_event
  [ "$event" = "$CLEAR" ]
  quiet 0.1
}

@test "summary and body become plain single-line text" {
  start_listener
  post 42 '<b>Andi</b> &amp; Budi' $'Halo   "kamu"\n<i>baris</i>\t&lt;2&gt; &#39;x&#39; &quot;y&quot;'
  next_event
  [ "$(summary)" = 'Andi & Budi' ]
  [ "$(jq -r .body <<< "$event")" = "Halo \"kamu\" baris <2> 'x' \"y\"" ]
}

@test "an icon file becomes a percent-encoded file URI; a missing one falls back to the bell" {
  local icon="$BATS_TEST_TMPDIR/icons dir/my icon#1.png"
  mkdir -p "${icon%/*}"
  : > "$icon"
  start_listener
  post 43 Foto '' NORMAL app "$icon"
  post 44 Lain '' NORMAL app "$BATS_TEST_TMPDIR/missing.png"
  next_event
  [ "$(jq -r .image <<< "$event")" = "file://$(jq -rn --arg p "$icon" '$p | split("/") | map(@uri) | join("/")')" ]
  next_event
  [ "$(jq -c '[.id,.image]' <<< "$event")" = '[44,""]' ]
  [ "$(jq -r .icon <<< "$event")" = "$BELL" ]
}

@test "queued notifications show one after another for a full hold each" {
  start_listener
  post 1 A
  post 2 B
  next_event
  [ "$(summary)" = A ]
  quiet 0.2
  next_event
  [ "$(summary)" = B ]
  quiet 0.2
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "more than three waiting notifications collapse into one +N entry" {
  start_listener
  local id
  for id in 1 2 3 4 5 6; do post "$id" "N$id"; done
  local shown=()
  for id in 1 2 3 4 5; do next_event; shown+=("$(summary)"); done
  [ "${shown[*]}" = 'N1 N2 N3 N4 +2 notifikasi' ]
  [ "$(jq -c '[.active,.id,.body,.image,.critical]' <<< "$event")" = '[true,0,"","",false]' ]
  [ "$(jq -r .icon <<< "$event")" = "$BELL" ]
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "an update with the same id replaces the notification in place, shown or queued" {
  start_listener
  post 7 Unduh '10%'
  next_event
  [ "$(jq -r .body <<< "$event")" = '10%' ]
  post 7 Unduh '60%'
  next_event 0.1
  [ "$(jq -c '[.id,.body]' <<< "$event")" = '[7,"60%"]' ]
  post 8 Salin '1'
  post 8 Salin '2'
  quiet 0.2
  next_event
  [ "$(jq -c '[.id,.body]' <<< "$event")" = '[8,"2"]' ]
  quiet 0.2
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "a notification with the same app and stack tag replaces the previous one" {
  start_listener
  post 10 Lagu a NORMAL spotify '' '' now
  next_event
  post 11 Lagu b NORMAL spotify '' '' now
  next_event 0.1
  [ "$(jq -c '[.id,.body]' <<< "$event")" = '[11,"b"]' ]
  quiet 0.2
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "critical notifications are flagged" {
  start_listener
  post 12 Baterai habis CRITICAL
  next_event
  [ "$(jq -c '[.id,.critical]' <<< "$event")" = '[12,true]' ]
}

@test "the island's own failures and OSD stack tags never reach the island" {
  start_listener
  post 13 'island gagal' x CRITICAL eww-island
  post 14 Volume '' NORMAL pactl '' '' obvolume
  post 15 Kecerahan '' NORMAL light '' '' obbacklight
  quiet 0.2
  post 16 Ok
  next_event
  [ "$(jq -r .id <<< "$event")" = 16 ]
}

@test "notifications are dropped while dunst is paused" {
  start_listener
  printf 'true\n' > "$NOTIFY_FIXTURE/paused"
  post 17 Diam
  quiet 0.2
  printf 'false\n' > "$NOTIFY_FIXTURE/paused"
  post 18 Bunyi
  next_event
  [ "$(jq -r .id <<< "$event")" = 18 ]
}

@test "an alert pauses the hold and the remaining hold resumes after it clears" {
  start_listener
  post 20 A
  next_event
  sleep 0.15
  signal '@alert 1'
  quiet 0.4
  signal '@alert 0'
  quiet 0.08
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "a notification arriving during an alert waits until the alert clears" {
  start_listener
  signal '@alert 1'
  post 21 Antre
  quiet 0.2
  signal '@alert 0'
  next_event
  [ "$(jq -r .id <<< "$event")" = 21 ]
}

@test "an expanded island defers notifications and pauses the shown one" {
  start_listener
  signal '@expanded 1'
  post 22 Nanti
  quiet 0.2
  signal '@expanded 0'
  next_event
  [ "$(jq -r .id <<< "$event")" = 22 ]
  sleep 0.1
  signal '@expanded 1'
  quiet 0.4
  signal '@expanded 0'
  quiet 0.08
  next_event
  [ "$event" = "$CLEAR" ]
}

@test "a notification waits until both the alert and the expanded island are gone" {
  start_listener
  signal '@alert 1'
  signal '@expanded 1'
  post 23 Tunggu
  signal '@alert 0'
  quiet 0.15
  signal '@expanded 0'
  next_event
  [ "$(jq -r .id <<< "$event")" = 23 ]
}

@test "clicking dismisses the notification and activates its app window" {
  export ISLAND_NOTIFY_SECONDS=2
  printf 'firefox 42\n' > "$NOTIFY_FIXTURE/windows"
  start_listener
  post 30 Pesan baru NORMAL Firefox '' firefox
  next_event
  run "$SCRIPTS/notify" click 30
  [ "$status" -eq 0 ]
  next_event 0.5
  [ "$event" = "$CLEAR" ]
  wait_for_line "$NOTIFY_FIXTURE/xdotool.log" 'windowactivate 42'
  run ! grep -q '^close' "$NOTIFY_FIXTURE/dunstctl.log"
}

@test "click finds the window through the desktop entry's StartupWMClass" {
  export ISLAND_NOTIFY_SECONDS=2
  mkdir -p "$XDG_DATA_DIRS/applications"
  printf '[Desktop Entry]\nName=Telegram\nStartupWMClass=TelegramDesktop\n' \
    > "$XDG_DATA_DIRS/applications/org.telegram.desktop.desktop"
  printf 'TelegramDesktop 77\n' > "$NOTIFY_FIXTURE/windows"
  start_listener
  post 31 Andi halo NORMAL 'Telegram Desktop' '' org.telegram.desktop
  next_event
  "$SCRIPTS/notify" click 31
  next_event 0.5
  [ "$event" = "$CLEAR" ]
  wait_for_line "$NOTIFY_FIXTURE/xdotool.log" 'windowactivate 77'
}

@test "a stale click for a notification no longer shown changes nothing" {
  export ISLAND_NOTIFY_SECONDS=2
  printf 'app 5\n' > "$NOTIFY_FIXTURE/windows"
  start_listener
  post 33 Masih
  next_event
  "$SCRIPTS/notify" click 99
  quiet 0.3
  run ! grep -q windowactivate "$NOTIFY_FIXTURE/xdotool.log"
}

@test "clicks walk the queue and the +N entry is only dismissed" {
  export ISLAND_NOTIFY_SECONDS=2
  start_listener
  local id
  for id in 1 2 3 4 5 6; do post "$id" "N$id"; done
  next_event
  for id in 1 2 3 4; do
    "$SCRIPTS/notify" click "$id"
    next_event 0.5
  done
  [ "$(jq -c '[.id,.summary]' <<< "$event")" = '[0,"+2 notifikasi"]' ]
  "$SCRIPTS/notify" click 0
  next_event 0.5
  [ "$event" = "$CLEAR" ]
  run ! grep -q windowactivate "$NOTIFY_FIXTURE/xdotool.log"
}

@test "click without a running listener exits quietly" {
  run timeout 2 "$SCRIPTS/notify" click 5
  [ "$status" -eq 0 ]
  [ ! -e "$FIFO" ]
}

@test "listener exit removes its fifo" {
  start_listener
  kill "$listener_pid"
  wait "$listener_pid" 2>/dev/null || :
  listener_pid=''
  [ ! -e "$FIFO" ]
}

@test "click without an app window launches the desktop entry, or only dismisses without one" {
  export ISLAND_NOTIFY_SECONDS=2
  start_listener
  post 34 Unduhan selesai NORMAL Files '' org.gnome.Nautilus
  next_event
  "$SCRIPTS/notify" click 34
  next_event 0.5
  [ "$event" = "$CLEAR" ]
  wait_for_line "$NOTIFY_FIXTURE/gtk-launch.log" org.gnome.Nautilus
  post 35 Skrip selesai NORMAL notify-send
  next_event
  "$SCRIPTS/notify" click 35
  next_event 0.5
  [ "$event" = "$CLEAR" ]
  sleep 0.2
  [ "$(cat "$NOTIFY_FIXTURE/gtk-launch.log")" = org.gnome.Nautilus ]
  run ! grep -q windowactivate "$NOTIFY_FIXTURE/xdotool.log"
}
