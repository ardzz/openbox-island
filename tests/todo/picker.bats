# tests/todo/picker.bats: the in-island deadline picker (state, commands and JSON).
load ../helpers
load common
bats_require_minimum_version 1.5.0

pin_clock() { export ISLAND_NOW=1792551600 TZ=Asia/Jakarta; } # Wed 2026-10-21 10:00
CLOSED='{"show":false,"id":0,"text":"","month_label":"","weeks":[],"hour":"","minute":"","summary":""}'
picker() { jq -c .picker <<< "$event"; }
cell() { jq -c --arg d "$1" '[.picker.weeks[][] | select(.date == $d)][0]' <<< "$event"; }
hm() { jq -c '[.picker.hour,.picker.minute]' <<< "$event"; }
head_picker() { jq -c '[.picker.id,.picker.text,.picker.month_label,.picker.hour,.picker.minute,.picker.summary]' <<< "$event"; }

@test "the picker is closed until a deadline is opened" {
  todo add a
  start_listener
  [ "$(picker)" = "$CLOSED" ]
}

@test "due opens the picker on today at 17:00 while that time is still ahead" {
  pin_clock
  todo add a
  start_listener
  local id; id=$(id_of a)
  run todo due "$id"
  [ "$status" -eq 0 ]
  next_event
  [ "$(jq -c .picker.show <<< "$event")" = 'true' ]
  [ "$(head_picker)" = "[$id,\"a\",\"Oktober 2026\",\"17\",\"00\",\"Rab 21 Okt · 17:00\"]" ]
  grep -q '^eww update island_tab=tugas' "$FIX/calls"
}

@test "due on another item moves the picker to that item" {
  pin_clock
  add_all a b
  start_listener
  local ida idb; ida=$(id_of a); idb=$(id_of b)
  todo due "$ida"; next_event
  [ "$(jq -r .picker.text <<< "$event")" = 'a' ]
  todo due "$idb"; next_event
  [ "$(head_picker)" = "[$idb,\"b\",\"Oktober 2026\",\"17\",\"00\",\"Rab 21 Okt · 17:00\"]" ]
}

@test "after 17:00 the default deadline is tomorrow at 17:00" {
  export ISLAND_NOW=1792580400 TZ=Asia/Jakarta # Wed 2026-10-21 18:00
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(head_picker)" = '[1,"a","Oktober 2026","17","00","Kam 22 Okt · 17:00"]' ]
  [ "$(cell 2026-10-22)" = '{"date":"2026-10-22","day":"22","cls":"sel"}' ]
}

@test "at exactly 17:00 the default deadline is already tomorrow" {
  export ISLAND_NOW=1792576800 TZ=Asia/Jakarta # Wed 2026-10-21 17:00
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(jq -r .picker.summary <<< "$event")" = 'Kam 22 Okt · 17:00' ]
}

@test "the default time follows ISLAND_DEADLINE_TIME" {
  pin_clock
  export ISLAND_DEADLINE_TIME=09:30
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(head_picker)" = '[1,"a","Oktober 2026","09","30","Kam 22 Okt · 09:30"]' ]
}

@test "an existing deadline opens on its date and time, odd minutes kept" {
  pin_clock
  todo add a --due 1793327820 # Fri 2026-10-30 09:37
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(head_picker)" = '[1,"a","Oktober 2026","09","37","Jum 30 Okt · 09:37"]' ]
  [ "$(cell 2026-10-30)" = '{"date":"2026-10-30","day":"30","cls":"sel"}' ]
}

@test "an existing deadline in another month opens on that month" {
  pin_clock
  todo add a --due 1796092620 # Tue 2026-12-01 09:37
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(head_picker)" = '[1,"a","Desember 2026","09","37","Sel 1 Des · 09:37"]' ]
  [ "$(jq -r '.picker.weeks[0][0].date' <<< "$event")" = '2026-11-30' ]
  [ "$(cell 2026-12-01)" = '{"date":"2026-12-01","day":"1","cls":"sel"}' ]
}

@test "the calendar is always 6 by 7, Monday first, with other, past, today and sel classes" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  [ "$(jq -c '[(.picker.weeks | length), ([.picker.weeks[] | length])]' <<< "$event")" = '[6,[7,7,7,7,7,7]]' ]
  [ "$(jq -r '.picker.weeks[0][0].date' <<< "$event")" = '2026-09-28' ]
  [ "$(jq -r '.picker.weeks[5][6].date' <<< "$event")" = '2026-11-08' ]
  [ "$(cell 2026-09-28)" = '{"date":"2026-09-28","day":"28","cls":"other past"}' ]
  [ "$(cell 2026-10-01)" = '{"date":"2026-10-01","day":"1","cls":"past"}' ]
  [ "$(cell 2026-10-20)" = '{"date":"2026-10-20","day":"20","cls":"past"}' ]
  [ "$(cell 2026-10-21)" = '{"date":"2026-10-21","day":"21","cls":"today sel"}' ]
  [ "$(cell 2026-10-22)" = '{"date":"2026-10-22","day":"22","cls":""}' ]
  [ "$(cell 2026-11-01)" = '{"date":"2026-11-01","day":"1","cls":"other"}' ]
}

@test "nav moves only the month shown, across the year boundary" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick nav 1; next_event
  [ "$(jq -c '[.picker.month_label,.picker.weeks[0][0].date,.picker.summary]' <<< "$event")" = '["November 2026","2026-10-26","Rab 21 Okt · 17:00"]' ]
  [ "$(jq -c '[.picker.weeks[][] | select(.cls | contains("sel"))] | length' <<< "$event")" = '0' ]
  todo pick nav 1; next_event
  [ "$(jq -c '[.picker.month_label,.picker.weeks[0][0].date]' <<< "$event")" = '["Desember 2026","2026-11-30"]' ]
  todo pick nav 1; next_event
  [ "$(jq -c '[.picker.month_label,.picker.weeks[0][0].date,.picker.weeks[5][6].date]' <<< "$event")" = '["Januari 2027","2026-12-28","2027-02-07"]' ]
  todo pick nav -1; next_event
  [ "$(jq -r .picker.month_label <<< "$event")" = 'Desember 2026' ]
  todo pick nav -1; next_event
  todo pick nav -1; next_event
  [ "$(jq -c '[.picker.month_label,.picker.summary]' <<< "$event")" = '["Oktober 2026","Rab 21 Okt · 17:00"]' ]
  [ "$(cell 2026-10-21)" = '{"date":"2026-10-21","day":"21","cls":"today sel"}' ]
}

@test "picking a past day is ignored and picking a day keeps the time" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  run todo pick day 2026-10-20
  [ "$status" -eq 0 ]
  quiet 0.3
  todo pick day 2026-10-23; next_event
  [ "$(jq -r .picker.summary <<< "$event")" = 'Jum 23 Okt · 17:00' ]
  [ "$(cell 2026-10-23)" = '{"date":"2026-10-23","day":"23","cls":"sel"}' ]
  [ "$(cell 2026-10-21)" = '{"date":"2026-10-21","day":"21","cls":"today"}' ]
}

@test "hour steps wrap 0 to 23 and minute steps wrap by 5" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick time 23:55; next_event
  [ "$(hm)" = '["23","55"]' ]
  todo pick hour up; next_event
  [ "$(hm)" = '["00","55"]' ]
  todo pick minute up; next_event
  [ "$(hm)" = '["00","00"]' ]
  [ "$(jq -r .picker.summary <<< "$event")" = 'Rab 21 Okt · 00:00' ]
  todo pick hour down; next_event
  [ "$(hm)" = '["23","00"]' ]
  todo pick minute down; next_event
  [ "$(hm)" = '["23","55"]' ]
}

@test "pick time sets the hour and minute together" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick time 12:00; next_event
  [ "$(jq -c '[.picker.hour,.picker.minute,.picker.summary]' <<< "$event")" = '["12","00","Rab 21 Okt · 12:00"]' ]
}

@test "save stores the picked epoch, closes the picker and shows the new chip" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick day 2026-10-30; next_event
  todo pick time 09:00; next_event
  todo pick save; next_event
  [ "$(picker)" = "$CLOSED" ]
  next_event
  [ "$(jq -c '.items[0] | [.due,.reminded]' "$DATA")" = '[1793325600,[]]' ]
  [ "$(jq -c '[.rows[0].due_label,.rows[0].due_class]' <<< "$event")" = '["30 Okt",""]' ]
  todo due "$(jq -r '.items[0].id' "$DATA")"; next_event
  [ "$(jq -r .picker.summary <<< "$event")" = 'Jum 30 Okt · 09:00' ]
}

@test "save re-arms reminders exactly like set-due for a time already passed today" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick time 09:00; next_event
  todo pick save; next_event
  [ "$(picker)" = "$CLOSED" ]
  [ "$(jq -c '.items[0] | [.due,.reminded]' "$DATA")" = '[1792548000,["eve"]]' ]
}

@test "clear removes the deadline and closes the picker" {
  pin_clock
  todo add a --due 1793354400 # Fri 2026-10-30 17:00
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick clear; next_event
  [ "$(picker)" = "$CLOSED" ]
  next_event
  [ "$(jq -c '.items[0] | [has("due"),has("reminded")]' "$DATA")" = '[false,false]' ]
  [ "$(jq -r '.rows[0].due_label' <<< "$event")" = '' ]
}

@test "cancel closes the picker without changing the deadline" {
  pin_clock
  todo add a --due 1793354400
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick day 2026-10-23; next_event
  todo pick cancel; next_event
  [ "$(picker)" = "$CLOSED" ]
  [ "$(jq -c '.items[0].due' "$DATA")" = '1793354400' ]
}

@test "collapsing the card closes the picker without changing the deadline" {
  pin_clock
  todo add a --due 1793354400
  start_listener
  todo due "$(id_of a)"; next_event
  todo pick day 2026-10-23; next_event
  signal '@expanded 0'
  next_event
  [ "$(picker)" = "$CLOSED" ]
  [ "$(jq -c '.items[0].due' "$DATA")" = '1793354400' ]
}

@test "removing the item under the picker closes the picker" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  local pid; pid=$(jq -r .picker.id <<< "$event")
  todo remove "$pid"; next_event
  [ "$(picker)" = "$CLOSED" ]
  [ "$(texts)" = '[]' ]
}

@test "pick steps with no picker open change nothing" {
  pin_clock
  todo add a
  start_listener
  todo pick day 2026-10-23
  todo pick save
  quiet 0.3
  [ "$(jq -c '.items[0] | has("due")' "$DATA")" = 'false' ]
}

@test "due on an unknown id fails and sends nothing" {
  pin_clock
  todo add a
  start_listener
  : > "$FIX/calls"
  run todo due 999
  [ "$status" -eq 1 ]
  quiet 0.3
  [ ! -s "$FIX/calls" ]
  [ "$(jq -c '.items[0] | has("due")' "$DATA")" = 'false' ]
}

@test "malformed due and pick arguments are usage errors and send nothing" {
  pin_clock
  todo add a
  start_listener
  todo due "$(id_of a)"; next_event
  run todo due x; [ "$status" -eq 2 ]
  run todo due; [ "$status" -eq 2 ]
  run todo due 1 extra; [ "$status" -eq 2 ]
  run todo pick; [ "$status" -eq 2 ]
  run todo pick nav; [ "$status" -eq 2 ]
  run todo pick nav 0; [ "$status" -eq 2 ]
  run todo pick nav 2; [ "$status" -eq 2 ]
  run todo pick nav up; [ "$status" -eq 2 ]
  run todo pick day; [ "$status" -eq 2 ]
  run todo pick day 2026-13-01; [ "$status" -eq 2 ]
  run todo pick day 2026-02-30; [ "$status" -eq 2 ]
  run todo pick day 21-10-2026; [ "$status" -eq 2 ]
  run todo pick day 2026-10-23 extra; [ "$status" -eq 2 ]
  run todo pick hour; [ "$status" -eq 2 ]
  run todo pick hour left; [ "$status" -eq 2 ]
  run todo pick minute sideways; [ "$status" -eq 2 ]
  run todo pick time 24:00; [ "$status" -eq 2 ]
  run todo pick time 9:00; [ "$status" -eq 2 ]
  run todo pick time 12:60; [ "$status" -eq 2 ]
  run todo pick time 1200; [ "$status" -eq 2 ]
  run todo pick save extra; [ "$status" -eq 2 ]
  run todo pick explode; [ "$status" -eq 2 ]
  quiet 0.3
  todo pick day 2026-10-23; next_event
  [ "$(jq -r .picker.summary <<< "$event")" = 'Jum 23 Okt · 17:00' ]
}
