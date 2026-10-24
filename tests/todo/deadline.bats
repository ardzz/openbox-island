# tests/todo/deadline.bats: deadline instants and reminder times (lib/todo/deadline.sh).
load ../helpers
bats_require_minimum_version 1.5.0

setup() {
  export TZ=Asia/Jakarta
  unset ISLAND_DEADLINE_TIME ISLAND_DEADLINE_EVE ISLAND_DEADLINE_DAY
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/todo/deadline.sh"
  NOW=1792551600 # Wed 2026-10-21 10:00
}

at() { date -d "$1" +%s; }
@test "deadline_at moves whole local days and sets the time" {
  [ "$(deadline_at "$NOW" -1 09:00)" = "$(at '2026-10-20 09:00')" ]
  [ "$(deadline_at "$NOW" 0 18:00)" = "$(at '2026-10-21 18:00')" ]
  [ "$(deadline_at "$NOW" 7 08:59)" = "$(at '2026-10-28 08:59')" ]
}

@test "passed keys list the eve and day reminders already due" {
  local due
  due=$(at '2026-10-22 17:00')
  [ "$(deadline_passed_keys "$due" "$(at '2026-10-21 08:59')")" = '[]' ]
  [ "$(deadline_passed_keys "$due" "$NOW")" = '["eve"]' ]
  [ "$(deadline_passed_keys "$due" "$(at '2026-10-22 09:00')")" = '["eve","day"]' ]
}

@test "a day reminder not before the deadline does not exist, and an empty setting disables one" {
  local due
  due=$(at '2026-10-23 08:00')
  [ "$(deadline_passed_keys "$due" "$(at '2026-10-23 07:59')")" = '["eve"]' ]
  export ISLAND_DEADLINE_EVE='' ISLAND_DEADLINE_DAY=07:00
  [ "$(deadline_passed_keys "$due" "$(at '2026-10-23 07:59')")" = '["day"]' ]
}

@test "titles say hari ini or besok relative to now" {
  [ "$(deadline_title "$(at '2026-10-21 17:00')" "$NOW")" = 'Deadline hari ini · 17:00' ]
  [ "$(deadline_title "$(at '2026-10-22 09:00')" "$NOW")" = 'Deadline besok · 09:00' ]
}

@test "days are counted on the calendar even where midnight is skipped" {
  export TZ=America/Santiago
  local due
  due=$(at '2026-09-06 17:00')
  [ "$(deadline_at "$due" 0 09:00)" = "$(at '2026-09-06 09:00')" ]
  [ "$(deadline_at "$due" -1 09:00)" = "$(at '2026-09-05 09:00')" ]
  [ "$(deadline_passed_keys "$due" "$(at '2026-09-06 10:00')")" = '["eve","day"]' ]
}
