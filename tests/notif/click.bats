load ../helpers
load common
bats_require_minimum_version 1.5.0

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
