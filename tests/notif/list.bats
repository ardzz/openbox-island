load ../helpers
load common
bats_require_minimum_version 1.5.0

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
