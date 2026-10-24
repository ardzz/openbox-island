# tests/upcoming/meeting.bats: the meeting part of the left pill.
load ../helpers
load common

@test "an ongoing meeting shows until its end with Join" {
  agenda "$(row 0000000000a1 "$(at 09:30)" "$(at 10:30)" Standup https://meet.google.com/abc-defg-hij)" \
    "$(row 0000000000a2 "$(at 10:05)" "$(at 10:30)" Sinkron)"
  shown
  [ "$(jq -c .meeting <<< "$event")" = '{"show":true,"id":"0000000000a1","title":"Standup","text":"sampai 10:30","state":"now","color":"#4f8cff","join":true}' ]
}

@test "a meeting within 15 minutes counts down in whole minutes, rounded up" {
  agenda "$(row 0000000000b1 $(( ISLAND_NOW + 701 )) "$(at 10:30)" Review https://zoom.us/j/1)"
  shown
  [ "$(m state) $(m text) $(m join)" = 'soon 12m true' ]
  agenda "$(row 0000000000b1 $(( ISLAND_NOW + 900 )) "$(at 10:30)" Review)"
  shown
  [ "$(m state) $(m text) $(m join)" = 'soon 15m false' ]
}

@test "a meeting more than 15 minutes away shows its start time without Join" {
  agenda "$(row 0000000000c1 $(( ISLAND_NOW + 901 )) "$(at 11:00)" Planning https://meet.google.com/abc-defg-hij)"
  shown
  [ "$(m state) $(m text) $(m join)" = 'later 10:15 false' ]
}

@test "ended meetings are skipped and an ongoing one wins over a sooner start" {
  agenda "$(row 0000000000d1 "$(at 09:00)" "$(at 10:00)" Selesai)" \
    "$(row 0000000000d2 "$(at 09:45)" "$(at 11:00)" Workshop)" \
    "$(row 0000000000d3 "$(at 10:05)" "$(at 10:30)" Sinkron)"
  shown
  [ "$(m title) $(m state)" = 'Workshop now' ]
}

@test "with nothing left today, tomorrow's first meeting shows" {
  agenda "$(row 0000000000e1 "$(at 08:00)" "$(at 09:00)" Pagi)" \
    "$(row 0000000000e2 "$(at 09:00 1)" "$(at 09:30 1)" Standup https://meet.google.com/abc-defg-hij Besok)"
  shown
  [ "$(m title) | $(m state) | $(m text) | $(m join)" = 'Standup | tomorrow | Besok 09:00 | false' ]
}

@test "a zero-length meeting counts as one minute long" {
  agenda "$(row 0000000000f1 $(( ISLAND_NOW - 30 )) $(( ISLAND_NOW - 30 )) Pengingat)"
  shown
  [ "$(m state) $(m text)" = 'now sampai 10:00' ]
}

@test "a link that is not plain https offers no Join" {
  agenda "$(row 0000000000g1 "$(at 09:30)" "$(at 10:30)" Standup http://meet.google.com/abc-defg-hij)"
  shown
  [ "$(m show) $(m join)" = 'true false' ]
}

@test "a missing, failed or malformed agenda hides the meeting" {
  shown
  [ "$(m show)" = false ]
  printf '{"ok":false,"error":"belum ada kalender di config","rows":[]}\n' > "$ST/agenda.json"
  shown
  [ "$(m show)" = false ]
  printf 'not json\n' > "$ST/agenda.json"
  shown
  [ "$(m show)" = false ]
  printf '{"ok":true,"rows":[1,2]}\n' > "$ST/agenda.json"
  shown
  [ "$(m show)" = false ]
}

@test "a new agenda shows within a tick" {
  start_listener
  [ "$(m show)" = false ]
  agenda "$(row 0000000000h1 "$(at 14:00)" "$(at 15:00)" Demo)"
  next_event 2
  [ "$(m title) $(m text)" = 'Demo 14:00' ]
}
