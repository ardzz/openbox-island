# tests/kalender/view.bats: the Kalender tab from agenda.json.
load ../helpers
load common
bats_require_minimum_version 1.5.0

@test "the tab starts at the first event not yet over, with today's all-day titles" {
  agenda past past now later later later
  start_listener
  [ "$(titles)" = '["r3","r4","r5","r6"]' ]
  [ "$(jq -c '[.ok,.label,.offset,.more,.total,.allday_text,.note]' <<< "$event")" = '[true,"Kalender 2",2,0,6,"Cuti Bersama · Konferensi",""]' ]
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

@test "the note shows feed errors first, else an outdated agenda's update time" {
  agenda later
  edit_agenda '.errors = ["Pribadi: HTTP 401"] | .stale = true'
  start_listener
  [ "$(jq -r .note <<< "$event")" = 'Pribadi: HTTP 401' ]
  edit_agenda '.errors = []'
  next_event 2
  [ "$(jq -r .note <<< "$event")" = 'diperbarui 09:55' ]
}

@test "without an agenda the tab is not ok, and a producer failure is the note" {
  start_listener
  [ "$(jq -c '[.ok,.rows,.note]' <<< "$event")" = '[false,[],""]' ]
  printf '{"ok":false,"stale":false,"updated":"","error":"python-icalendar belum terpasang","label":"Kalender","remaining":0,"allday":[],"next":null,"rows":[],"errors":[]}\n' > "$ST/agenda.json"
  next_event 2
  [ "$(jq -c '[.ok,.note]' <<< "$event")" = '[false,"python-icalendar belum terpasang"]' ]
}

@test "a broken agenda file reads as not ok" {
  printf 'not json' > "$ST/agenda.json"
  start_listener
  [ "$(jq -c '[.ok,.rows]' <<< "$event")" = '[false,[]]' ]
}
