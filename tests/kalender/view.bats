# tests/kalender/view.bats: the Kalender tab from agenda.json.
load ../helpers
load common
bats_require_minimum_version 1.5.0

# prep_item ROW_ID TEXT DONE ID: one Tugas item marked as prep for ROW_ID.
prep_item() {
  jq -nc --arg prep "$1" --arg text "$2" --argjson done "$3" --argjson id "$4" \
    '{id: $id, text: $text, done: $done, created: 0, prep: $prep}'
}
# prep_todos ITEM...: write todo.json holding ITEMs under a fresh XDG_DATA_HOME.
prep_todos() {
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  mkdir -p "$XDG_DATA_HOME/eww-island"
  printf '%s\n' "$@" | jq -sc '{next_id: 100, items: .}' > "$XDG_DATA_HOME/eww-island/todo.json"
}
@test "the tab starts at the first event not yet over, with today's all-day titles" {
  agenda past past now later later later
  start_listener
  [ "$(titles)" = '["r3","r4","r5","r6"]' ]
  [ "$(jq -c '[.ok,.label,.count,.offset,.more,.total,.allday_text,.note]' <<< "$event")" = '[true,"Kalender 2",2,2,0,6,"Cuti Bersama · Konferensi",""]' ]
}

@test "a short agenda shows whole, past events included" {
  agenda past later
  start_listener
  [ "$(titles)" = '["r1","r2"]' ]
}

@test "scrolling up shows earlier events and the view holds until the card closes" {
  agenda past past now later later later
  start_listener
  kalender scroll up; next_event
  [ "$(titles)" = '["r2","r3","r4","r5"]' ]
  quiet 0.6
  signal '@expanded 0'; next_event
  [ "$(titles)" = '["r3","r4","r5","r6"]' ]
}

@test "a rewritten agenda shows on the next tick" {
  agenda later later
  start_listener
  agenda past past past now later later
  next_event 2
  [ "$(titles)" = '["r3","r4","r5","r6"]' ]
}

@test "the note shows feed errors alongside an outdated agenda's update time" {
  agenda later
  edit_agenda '.errors = ["Pribadi: HTTP 401"] | .stale = true'
  start_listener
  [ "$(jq -r .note <<< "$event")" = 'Pribadi: HTTP 401 · diperbarui 09:55' ]
  edit_agenda '.errors = []'
  next_event 2
  [ "$(jq -r .note <<< "$event")" = 'diperbarui 09:55' ]
}

@test "without an agenda the tab is not ok, and a producer failure is the note" {
  start_listener
  [ "$(jq -c '[.ok,.count,.rows,.note]' <<< "$event")" = '[false,0,[],""]' ]
  printf '{"ok":false,"stale":false,"updated":"","error":"python-icalendar belum terpasang","label":"Kalender","remaining":0,"allday":[],"next":null,"rows":[],"errors":[]}\n' > "$ST/agenda.json"
  next_event 2
  [ "$(jq -c '[.ok,.note]' <<< "$event")" = '[false,"python-icalendar belum terpasang"]' ]
}

@test "a broken agenda file reads as not ok" {
  printf 'not json' > "$ST/agenda.json"
  start_listener
  [ "$(jq -c '[.ok,.rows]' <<< "$event")" = '[false,[]]' ]
}

@test "a row with two prep items one done shows 1/2 not done" {
  agenda later later
  prep_todos "$(prep_item 000000000001 'Weekly Report · Report progres' true 1)" \
             "$(prep_item 000000000001 'Weekly Report · Plan minggu depan' false 2)" \
             "$(prep_item 000000000002 'Lain · Abaikan' false 3)"
  start_listener
  [ "$(jq -c '[.rows[0].prep, .rows[0].prep_done]' <<< "$event")" = '["1/2",false]' ]
  [ "$(jq -c '[.rows[1].prep, .rows[1].prep_done]' <<< "$event")" = '["0/1",false]' ]
}

@test "a row with all prep items done shows 2/2 done" {
  agenda later
  prep_todos "$(prep_item 000000000001 'Weekly Report · Report progres' true 1)" \
             "$(prep_item 000000000001 'Weekly Report · Plan minggu depan' true 2)"
  start_listener
  [ "$(jq -c '[.rows[0].prep, .rows[0].prep_done]' <<< "$event")" = '["2/2",true]' ]
}

@test "a row with no prep items shows empty prep" {
  agenda later later
  prep_todos "$(prep_item 000000000002 'Lain · Abaikan' false 1)" \
             '{"id":9,"text":"Tugas biasa","done":false,"created":0}'
  start_listener
  [ "$(jq -c '[.rows[0].prep, .rows[0].prep_done]' <<< "$event")" = '["",false]' ]
  [ "$(jq -c '[.rows[1].prep, .rows[1].prep_done]' <<< "$event")" = '["0/1",false]' ]
}
