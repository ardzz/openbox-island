# tests/tab/registry.bats
load ../helpers
load common

@test "the notification tab is offered while the center has entries" {
  no_music; no_weather; notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = notif ]
  no_notif; weather; saved notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
}

@test "the notification tab comes after music and weather" {
  both; notif; shown cuaca
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = notif ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = musik ]
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "select tells the notification center which tab is shown" {
  both; notif
  mkfifo "$ST/notif.fifo"
  exec {notif_fd}<> "$ST/notif.fifo"
  run "$SCRIPTS/tab" select notif
  [ "$status" -eq 0 ]
  IFS= read -r -t 1 -u "$notif_fd" line
  [ "$line" = '@tab notif' ]
  [ "$(calls)" = 'update island_tab=notif' ]
}

@test "the to-do tab is offered while its list listener runs, even with nothing else" {
  no_music; no_weather; no_notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
  mkfifo "$ST/todo.fifo"
  run "$SCRIPTS/tab" resolve
  [ "$output" = tugas ]
  run "$SCRIPTS/tab" select tugas
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/tab")" = tugas ]
}

@test "the to-do tab is offered while the list has an open item, even with its listener stopped" {
  no_music; no_weather; no_notif; open_todo
  run "$SCRIPTS/tab" resolve
  [ "$output" = tugas ]
  run "$SCRIPTS/tab" resolve tugas
  [ "$output" = tugas ]
  open_todo true
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
  run "$SCRIPTS/tab" resolve tugas
  [ "$output" = musik ]
}

@test "the to-do tab is offered for a pending picker request on a completed-only list" {
  no_music; no_weather; no_notif; open_todo true
  run "$SCRIPTS/tab" resolve tugas
  [ "$output" = musik ]
  mkdir -p "$ST"; echo 1 > "$ST/todo-pick"
  run "$SCRIPTS/tab" resolve tugas
  [ "$output" = tugas ]
  run "$SCRIPTS/tab" resolve
  [ "$output" = tugas ]
}

@test "the to-do tab comes after notifications" {
  both; notif; shown notif; mkfifo "$ST/todo.fifo"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = tugas ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = musik ]
}

@test "the shortcuts tab is offered while its config has a shortcut" {
  no_music; no_weather; no_notif; shortcuts
  run "$SCRIPTS/tab" resolve
  [ "$output" = pintasan ]
  printf '# kosong\n\nrusak tanpa kolom\n' > "$ISLAND_SHORTCUTS"
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
}

@test "music, weather and notifications come before shortcuts when nothing is saved" {
  no_weather; no_notif; shortcuts; music
  run "$SCRIPTS/tab" resolve
  [ "$output" = musik ]
  no_music; weather
  run "$SCRIPTS/tab" resolve
  [ "$output" = cuaca ]
  no_weather; notif
  run "$SCRIPTS/tab" resolve
  [ "$output" = notif ]
}

@test "a saved shortcuts tab reopens" {
  both; notif; shortcuts; saved pintasan
  run "$SCRIPTS/tab" resolve
  [ "$output" = pintasan ]
}

@test "the shortcuts tab comes last and wraps to the first" {
  both; notif; shortcuts; shown notif
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = pintasan ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = musik ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" prev
  [ "$(cat "$FAKE_TAB")" = pintasan ]
}

@test "select accepts the shortcuts tab" {
  shortcuts
  run "$SCRIPTS/tab" select pintasan
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/tab")" = pintasan ]
  [ "$(calls)" = 'update island_tab=pintasan' ]
}

@test "the to-do tab sits between notifications and shortcuts" {
  both; notif; shortcuts; shown notif; mkfifo "$ST/todo.fifo"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = tugas ]
  rm -f "$ST/tab_at"
  run "$SCRIPTS/tab" next
  [ "$(cat "$FAKE_TAB")" = pintasan ]
}

@test "the quota tab is available from a successful collector cache" {
  no_music; no_weather; no_notif
  printf '{"ok":true,"accounts":[]}\n' > "$ST/kuota.json"
  run "$SCRIPTS/tab" resolve kuota
  [ "$output" = kuota ]
  run "$SCRIPTS/tab" select kuota
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/tab")" = kuota ]
}

@test "the quota tab is unavailable without a successful cache" {
  no_music; no_weather; no_notif
  run "$SCRIPTS/tab" resolve kuota
  [ "$output" = musik ]
  printf '{"ok":false,"accounts":[]}\n' > "$ST/kuota.json"
  run "$SCRIPTS/tab" resolve kuota
  [ "$output" = musik ]
}
