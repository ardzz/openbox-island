# tests/todo/deadline.bats: parsing deadlines and reminder times (lib/todo/deadline.sh).
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
parses() { run deadline_parse "$1" "$NOW"; [ "$status" -eq 0 ]; [ "$output" = "$(at "$2")" ]; }
rejects() { run deadline_parse "$1" "$NOW"; [ "$status" -ne 0 ]; [ -z "$output" ]; }

@test "relative days take an optional time and default to 17:00" {
  parses 'hari ini' '2026-10-21 17:00'
  parses 'Besok 09:00' '2026-10-22 09:00'
  parses '  LUSA   jam 8 ' '2026-10-23 08:00'
  parses 'besok 14.30' '2026-10-22 14:30'
  parses 'besok jam 14:30' '2026-10-22 14:30'
}

@test "a bare time is today, or tomorrow once it is not ahead" {
  parses '14:00' '2026-10-21 14:00'
  parses '09:00' '2026-10-22 09:00'
  parses 'jam 10' '2026-10-22 10:00'
  parses 'jam 14.30' '2026-10-21 14:30'
}

@test "weekdays mean the next such day, today only while the time is ahead" {
  parses 'jumat 17:00' '2026-10-23 17:00'
  parses 'senin' '2026-10-26 17:00'
  parses 'rabu 18:00' '2026-10-21 18:00'
  parses 'rabu 09:00' '2026-10-28 09:00'
}

@test "dates take Indonesian month names or day/month and roll into next year once past" {
  parses '28 okt 10:00' '2026-10-28 10:00'
  parses '28 Oktober' '2026-10-28 17:00'
  parses '2 nov' '2026-11-02 17:00'
  parses '5/1' '2027-01-05 17:00'
  parses '20 okt' '2027-10-20 17:00'
}

@test "the default time follows ISLAND_DEADLINE_TIME" {
  export ISLAND_DEADLINE_TIME=12:00
  parses 'besok' '2026-10-22 12:00'
}

@test "unknown, impossible or past input is rejected" {
  rejects ''
  rejects 'kapan-kapan'
  rejects 'besok 25:00'
  rejects 'besok 10:60'
  rejects '31 feb'
  rejects '13/13'
  rejects 'hari ini 08:00'
  rejects 'besok besok'
}

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
