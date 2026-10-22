load ../helpers
load common
bats_require_minimum_version 1.5.0

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

@test "listener exit removes its fifo" {
  start_listener
  kill "$listener_pid"
  wait "$listener_pid" 2>/dev/null || :
  listener_pid=''
  [ ! -e "$FIFO" ]
}
