load ../helpers
load common
bats_require_minimum_version 1.5.0

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
