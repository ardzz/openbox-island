# tests/island/tabs.bats
load ../helpers
load common

@test "hover with nothing else to show opens the to-do tab while its list runs" {
  mkdir -p "$ST"; mkfifo "$ST/todo.fifo"
  stub_hover_sleep; on_compact; no_music
  run "$SCRIPTS/island" hover
  [ "$(calls)" = $'update island_reveal=false island_tab=tugas\nopen island-expanded\nupdate island_reveal=true' ]
}

@test "hover opens the card on the saved tab" {
  stub_hover_sleep; on_compact; music; weather; saved cuaca
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = $'update island_reveal=false island_tab=cuaca\nopen island-expanded\nupdate island_reveal=true' ]
}

@test "hover opens the first available tab when the saved one is unavailable" {
  stub_hover_sleep; on_compact; no_music; weather; saved musik
  run "$SCRIPTS/island" hover
  [ "$(calls)" = $'update island_reveal=false island_tab=cuaca\nopen island-expanded\nupdate island_reveal=true' ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "auto opens the card on music without overwriting the saved tab" {
  on_compact; music; weather; saved cuaca
  run "$SCRIPTS/island" auto 0
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$OPEN" ]
  [ "$(cat "$ST/tab")" = cuaca ]
}

@test "auto on an open card switches it to music" {
  expanded; on_expanded_only; music; weather; saved cuaca
  run "$SCRIPTS/island" auto 0
  [ "$(calls)" = 'update island_tab=musik island_reveal=true' ]
  [ "$(cat "$ST/tab")" = cuaca ]
}

@test "close on a hovered card whose music stopped falls back to weather" {
  expanded; on_expanded_only; no_music; weather; saved musik
  run "$SCRIPTS/island" close
  [ "$status" -eq 0 ]
  [ "$(calls)" = 'update island_tab=cuaca' ]
  [ "$(cat "$ST/tab")" = musik ]
}

@test "hover over the idle pill opens the shortcuts when nothing else has content" {
  stub_hover_sleep; on_compact; no_music; shortcuts
  run "$SCRIPTS/island" hover
  [ "$status" -eq 0 ]
  [ "$(calls)" = $'update island_reveal=false island_tab=pintasan\nopen island-expanded\nupdate island_reveal=true' ]
}

@test "hover prefers music over shortcuts when no tab is saved" {
  stub_hover_sleep; on_compact; music; shortcuts
  run "$SCRIPTS/island" hover
  [ "$(calls)" = "$OPEN" ]
}

@test "auto opens the card on a given tab when it is available" {
  on_compact; music; agenda_ok
  run "$SCRIPTS/island" auto 0 kalender
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$FAKE_EWW_LOG")" = 'update island_reveal=false island_tab=kalender' ]
}

@test "auto on an unavailable tab leaves the island closed instead of opening another tab" {
  on_compact; music
  run "$SCRIPTS/island" auto 10 kalender
  [ "$status" -eq 0 ]
  [ "$(calls)" = "" ]
  [ "$(cat "$ST/auto_until" 2>/dev/null || echo 0)" = 0 ]
}

@test "auto opens the to-do tab for a deadline while its listener is stopped" {
  local data="${XDG_DATA_HOME}/eww-island/todo.json"
  mkdir -p "${data%/*}"
  printf '{"next_id":2,"items":[{"id":1,"text":"Laporan","done":false,"created":0,"due":1792558800}]}\n' > "$data"
  on_compact; music
  run "$SCRIPTS/island" auto 0 tugas
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$FAKE_EWW_LOG")" = 'update island_reveal=false island_tab=tugas' ]
}

@test "auto rejects a malformed tab name without touching eww" {
  run "$SCRIPTS/island" auto 5 'x y'
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_EWW_LOG" ]
}
