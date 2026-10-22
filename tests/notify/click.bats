load ../helpers
load common
bats_require_minimum_version 1.5.0

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
