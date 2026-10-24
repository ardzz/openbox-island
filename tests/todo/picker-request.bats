# tests/todo/picker-request.bats: picker-open requests that outlive the listener.
load ../helpers
load common
bats_require_minimum_version 1.5.0

pin_clock() { export ISLAND_NOW=1792551600 TZ=Asia/Jakarta; } # Wed 2026-10-21 10:00
CLOSED='{"show":false,"id":0,"text":"","month_label":"","weeks":[],"hour":"","minute":"","summary":""}'
picker() { jq -c .picker <<< "$event"; }
head_picker() { jq -c '[.picker.id,.picker.text,.picker.month_label,.picker.hour,.picker.minute,.picker.summary]' <<< "$event"; }

@test "a due request with no listener running opens the picker when the listener starts" {
  pin_clock
  todo add a
  local id; id=$(jq -r '.items[0].id' "$DATA")
  run todo due "$id"
  [ "$status" -eq 0 ]
  [ ! -p "$FIFO" ]
  [ "$(cat "$ST/todo-pick")" = "$id" ]
  grep -q '^eww update island_tab=tugas' "$FIX/calls"
  start_listener
  [ "$(head_picker)" = "[$id,\"a\",\"Oktober 2026\",\"17\",\"00\",\"Rab 21 Okt · 17:00\"]" ]
  todo pick cancel; next_event
  [ "$(picker)" = "$CLOSED" ]
  [ ! -e "$ST/todo-pick" ]
}

@test "due on a completed-only list still offers Tugas and opens the picker" {
  pin_clock
  todo add a
  todo toggle 1
  [ "$(jq -c '[.items[0].done, has("due")]' "$DATA")" = '[true,false]' ]
  local id; id=$(jq -r '.items[0].id' "$DATA")
  run todo due "$id"
  [ "$status" -eq 0 ]
  [ "$(cat "$ST/todo-pick")" = "$id" ]
  [ "$("$SCRIPTS/tab" resolve tugas)" = tugas ]
  grep -q '^eww update island_tab=tugas' "$FIX/calls"
  start_listener
  [ "$(head_picker)" = "[$id,\"a\",\"Oktober 2026\",\"17\",\"00\",\"Rab 21 Okt · 17:00\"]" ]
}

@test "due waits for the island lock so a closing card cannot delete its request" {
  pin_clock
  todo add a
  local id; id=$(jq -r '.items[0].id' "$DATA")
  # A closing card holds the island lock, then deletes the request before releasing.
  ( exec 9>"$ST/lock"; flock 9; echo held > "$FIX/held"; sleep 0.5; rm -f "$ST/todo-pick" ) &
  local closer=$!
  for _ in {1..100}; do [ -e "$FIX/held" ] && break; sleep 0.01; done
  [ -e "$FIX/held" ]
  run todo due "$id"
  [ "$status" -eq 0 ]
  wait "$closer"
  [ "$(cat "$ST/todo-pick")" = "$id" ]
  grep -q '^eww update island_tab=tugas' "$FIX/calls"
}

@test "closing the picker by save, clear, cancel, collapse or removal drops the open request" {
  pin_clock
  todo add a --due 1793354400
  todo add b
  start_listener
  local ida idb; ida=$(jq -r '.items[] | select(.text == "a") | .id' "$DATA"); idb=$(jq -r '.items[] | select(.text == "b") | .id' "$DATA")
  todo due "$ida"; next_event; [ -e "$ST/todo-pick" ]
  todo pick cancel; next_event; [ ! -e "$ST/todo-pick" ]
  todo due "$ida"; next_event
  todo pick clear; next_event; next_event; [ ! -e "$ST/todo-pick" ]
  todo due "$idb"; next_event
  todo pick save; next_event; next_event; [ ! -e "$ST/todo-pick" ]
  todo due "$idb"; next_event
  signal '@expanded 0'; next_event; [ ! -e "$ST/todo-pick" ]
  todo due "$idb"; next_event
  todo remove "$idb"; next_event; [ ! -e "$ST/todo-pick" ]
}

@test "a day whose midnight is skipped is still a valid pick day" {
  export TZ=America/Santiago ISLAND_NOW=1788699600 # Sun 2026-09-06 10:00, midnight skipped
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(jq -r .picker.summary <<< "$event")" = 'Min 6 Sep · 17:00' ]
  run todo pick day 2026-09-06
  [ "$status" -eq 0 ]
  todo pick day 2026-09-07; next_event
  [ "$(jq -r .picker.summary <<< "$event")" = 'Sen 7 Sep · 17:00' ]
  [ "$(jq -r .picker.month_label <<< "$event")" = 'September 2026' ]
}
