# tests/prep/sync.bats: creating prep items before matching meetings.
load common
bats_require_minimum_version 1.5.0
@test "a matching meeting 23h ahead gets one item per template entry and a ledger line" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  run prep_sync
  [ "$status" -eq 0 ]
  [ "$(items_json)" = "$(jq -nc --argjson due "$(at '2026-10-22 07:00')" '[
    {text:"Weekly Report · Report progres",done:false,due:$due,reminded:["eve"],prep:"aaaaaaaaaaaa"},
    {text:"Weekly Report · Plan minggu depan",done:false,due:$due,reminded:["eve"],prep:"aaaaaaaaaaaa"}]')" ]
  # created is pinned now in microseconds.
  [ "$(jq -c '[.items[].created]' "$TODO_FILE")" = "[${NOW}000000,${NOW}000000]" ]
  [ "$(cat "$PREP_LEDGER")" = "aaaaaaaaaaaa $(at '2026-10-22 09:00')" ]
}

@test "a second sync adds nothing, and deleting the items does not recreate them" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  prep_sync
  prep_sync
  [ "$(jq '.items | length' "$TODO_FILE")" -eq 2 ]
  jq -c '.items = []' "$TODO_FILE" > "$TODO_FILE.new" && mv "$TODO_FILE.new" "$TODO_FILE"
  prep_sync
  [ "$(jq '.items | length' "$TODO_FILE")" -eq 0 ]
  [ "$(cat "$PREP_LEDGER")" = "aaaaaaaaaaaa $(at '2026-10-22 09:00')" ]
}

@test "a meeting 25h ahead gets nothing until the clock moves within 24h" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 11:00')")"
  prep_sync
  [ ! -e "$TODO_FILE" ]
  export ISLAND_NOW=$(at '2026-10-21 11:00')
  prep_sync
  [ "$(jq -c '[.items[].text]' "$TODO_FILE")" = '["Weekly Report · Report progres","Weekly Report · Plan minggu depan"]' ]
  [ "$(jq -c '[.items[].due]' "$TODO_FILE")" = "[$(at '2026-10-22 09:00'),$(at '2026-10-22 09:00')]" ]
}

@test "an empty ISLAND_PREP_AHEAD disables sync, and ISLAND_PREP_AHEAD widens the window" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 11:00')")"
  ISLAND_PREP_AHEAD= prep_sync
  [ ! -e "$TODO_FILE" ]
  ISLAND_PREP_AHEAD=48 prep_sync
  [ "$(jq '.items | length' "$TODO_FILE")" -eq 2 ]
}

@test "a non-matching title and an agenda that is not ok get nothing" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Standup' "$(at '2026-10-22 09:00')")"
  prep_sync
  [ ! -e "$TODO_FILE" ]
  agenda_rows "$(row bbbbbbbbbbbb 'Weekly Report' "$(at '2026-10-22 09:00')")" false
  prep_sync
  [ ! -e "$TODO_FILE" ]
  [ ! -e "$PREP_LEDGER" ]
}

@test "a meeting already started or starting now gets nothing" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$NOW")"
  prep_sync
  [ ! -e "$TODO_FILE" ]
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$((NOW - 3600))")"
  prep_sync
  [ ! -e "$TODO_FILE" ]
}

@test "a meeting 1h ahead with 2j gets due = start" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-21 11:00')")"
  prep_sync
  [ "$(jq -c '[.items[].due]' "$TODO_FILE")" = "[$(at '2026-10-21 11:00'),$(at '2026-10-21 11:00')]" ]
  [ "$(jq -c '[.items[].reminded]' "$TODO_FILE")" = '[["eve","day"],["eve","day"]]' ]
}

@test "the CLI sync creates the items" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  run "$SCRIPTS/prep" sync
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.items[].text]' "$TODO_FILE")" = '["Weekly Report · Report progres","Weekly Report · Plan minggu depan"]' ]
  [ "$(cat "$PREP_LEDGER")" = "aaaaaaaaaaaa $(at '2026-10-22 09:00')" ]
}

@test "two concurrent CLI sync runs create each item once" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  "$SCRIPTS/prep" sync & local p1=$!
  "$SCRIPTS/prep" sync & local p2=$!
  wait "$p1"; local s1=$?
  wait "$p2"; local s2=$?
  [ "$s1" -eq 0 ]
  [ "$s2" -eq 0 ]
  [ "$(jq '.items | length' "$TODO_FILE")" -eq 2 ]
  [ "$(jq -c '[.items[].text] | sort' "$TODO_FILE")" = '["Weekly Report · Plan minggu depan","Weekly Report · Report progres"]' ]
  [ "$(wc -l < "$PREP_LEDGER")" -eq 1 ]
}

@test "ledger lines older than 7 days are dropped on the next write" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  mkdir -p "${PREP_LEDGER%/*}"
  printf 'cccccccccccc %s\ndddddddddddd %s\n' "$(at '2026-10-14 09:59')" "$(at '2026-10-14 10:00')" > "$PREP_LEDGER"
  prep_sync
  # 2026-10-14 09:59 is more than 7 days before now; exactly 7 days old is kept.
  [ "$(cat "$PREP_LEDGER")" = "dddddddddddd $(at '2026-10-14 10:00')
aaaaaaaaaaaa $(at '2026-10-22 09:00')" ]
}

@test "sourcing the alert script registers prep as an interval source after meeting" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  run bash -c 'source "$1"; printf "%s\n" "${ALERT_SOURCES[*]}"; declare -F prep_interval prep_snapshot >/dev/null' _ "$SCRIPTS/alert"
  [ "$status" -eq 0 ]
  [[ $output == *' meeting prep'* ]]
  run bash -c 'source "$1" >/dev/null 2>&1; source "$2/lib/alert/prep.sh"; prep_interval' _ "$SCRIPTS/alert" "$SCRIPTS"
  [ "$output" = '60' ]
  ISLAND_PREP_INTERVAL=15 run bash -c 'source "$1" >/dev/null 2>&1; source "$2/lib/alert/prep.sh"; prep_interval' _ "$SCRIPTS/alert" "$SCRIPTS"
  [ "$output" = '15' ]
  # shellcheck disable=SC1091
  DIR="$SCRIPTS" source "$SCRIPTS/lib/alert/prep.sh"
  prep_snapshot
}

@test "a failed add records nothing in the ledger" {
  template_weekly
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  # An unwritable todo directory makes every todo_change fail (root can still write).
  [ "$(id -u)" -ne 0 ] || skip 'running as root'
  chmod 555 "${TODO_FILE%/*}"
  run prep_sync
  [ "$status" -ne 0 ]
  [ "$status" -ne 127 ]
  chmod 755 "${TODO_FILE%/*}"
  [ ! -e "$PREP_LEDGER" ]
}
