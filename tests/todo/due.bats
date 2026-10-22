# tests/todo/due.bats: storing and changing deadlines.
load ../helpers
load common
bats_require_minimum_version 1.5.0

pin_clock() { export ISLAND_NOW=1792551600 TZ=Asia/Jakarta; } # Wed 2026-10-21 10:00

@test "add --due stores the deadline with no reminder fired yet" {
  pin_clock
  run todo add 'Laporan Q3' --due 1792749600
  [ "$status" -eq 0 ]
  [ "$(jq -c '.items[0] | [.text,.due,.reminded]' "$DATA")" = '["Laporan Q3",1792749600,[]]' ]
}

@test "reminders already due when a deadline is set count as fired" {
  pin_clock
  todo add a --due 1792663200
  [ "$(jq -c '.items[0].reminded' "$DATA")" = '["eve"]' ]
}

@test "set-due changes or clears a deadline and re-arms its reminders" {
  pin_clock
  todo add a --due 1792663200
  start_listener
  run todo set-due "$(id_of a)" 1793181600
  [ "$status" -eq 0 ]
  next_event
  [ "$(jq -c '.items[0] | [.due,.reminded]' "$DATA")" = '[1793181600,[]]' ]
  run todo set-due "$(id_of a)" none
  [ "$status" -eq 0 ]
  next_event
  [ "$(jq -c '.items[0] | [has("due"),has("reminded")]' "$DATA")" = '[false,false]' ]
}

@test "set-due on an unknown id changes nothing and malformed input is a usage error" {
  pin_clock
  todo add a
  run todo set-due 999 1793181600
  [ "$status" -eq 1 ]
  run todo set-due abc 1793181600
  [ "$status" -eq 2 ]
  run todo set-due 1 besok
  [ "$status" -eq 2 ]
  run todo set-due 1
  [ "$status" -eq 2 ]
  run todo add b --due soon
  [ "$status" -eq 2 ]
  run todo add b --when 1793181600
  [ "$status" -eq 2 ]
  [ "$(jq -c '[.items[] | [.text, has("due")]]' "$DATA")" = '[["a",false]]' ]
}

@test "a deadline that is not a number makes the stored list corrupt" {
  local bad failed=0
  mkdir -p "${DATA%/*}"
  for bad in '"due":"besok"' '"due":false' '"reminded":false'; do
    printf '{"next_id":2,"items":[{"id":1,"text":"x","done":false,%s}]}\n' "$bad" > "$DATA"
    start_listener
    [ "$(jq -c '.rows' <<< "$event")" = '[]' ] || {
      printf 'accepted corrupt field: %s\n' "$bad"
      failed=1
    }
    stop_listener
  done
  [ "$failed" -eq 0 ]
}

@test "lists saved before deadlines existed still load" {
  mkdir -p "${DATA%/*}"
  printf '{"next_id":2,"items":[{"id":1,"text":"lama","done":false,"created":1}]}\n' > "$DATA"
  start_listener
  [ "$(texts)" = '["lama"]' ]
}
