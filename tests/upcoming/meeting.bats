# tests/upcoming/meeting.bats: the meeting part of the left pill.
load ../helpers
load common

@test "an ongoing meeting shows until its end with Join" {
  agenda "$(row 0000000000a1 "$(at 09:30)" "$(at 10:30)" Standup https://meet.google.com/abc-defg-hij)" \
    "$(row 0000000000a2 "$(at 10:05)" "$(at 10:30)" Sinkron)"
  shown
  [ "$(jq -c .meeting <<< "$event")" = '{"show":true,"id":"0000000000a1","title":"Standup","text":"sampai 10:30","state":"now","color":"#4f8cff","join":true,"prep":"","prep_done":false}' ]
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

@test "with nothing left today, the next meeting on a later day shows with its day" {
  agenda "$(row 0000000000e1 "$(at 08:00)" "$(at 09:00)" Pagi)" \
    "$(row 0000000000e2 "$(at 09:00 5)" "$(at 09:30 5)" Standup https://meet.google.com/abc-defg-hij 'Sen 26 Okt')"
  shown
  [ "$(m title) | $(m state) | $(m text) | $(m join)" = 'Standup | ahead | Sen 26 Okt 09:00 | false' ]
  agenda "$(row 0000000000e1 "$(at 08:00)" "$(at 09:00)" Pagi)" \
    "$(row 0000000000e2 "$(at 09:00 1)" "$(at 09:30 1)" Standup https://meet.google.com/abc-defg-hij Besok)"
  shown
  [ "$(m title) | $(m state) | $(m text) | $(m join)" = 'Standup | ahead | Besok 09:00 | false' ]
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

@test "a month of long rows still shows the meeting and the deadline" {
  todos "$(item 1 Laporan "$(at 17:00)")"
  jq -nc --argjson now "$ISLAND_NOW" --arg long "$(printf 'x%.0s' {1..200})" '
    {ok: true, stale: false, updated: "09:55", error: "", label: "Kalender", remaining: 0, allday: [],
     next: null, errors: [],
     rows: [range(700) | {id: "0000000000z\(. % 10)", start: ($now - 600 + . * 3600),
       end: ($now + 1800 + . * 3600), title: (if . == 0 then "Standup" else $long end),
       account: "Kantor", color: "#4f8cff", join: "", day: "Hari ini", time: "", state: "later"}]}' \
    > "$ST/agenda.json"
  [ "$(wc -c < "$ST/agenda.json")" -gt 200000 ]
  shown
  [ "$(m show) $(m title) $(d show) $(d title)" = 'true Standup true Laporan' ]
}

@test "an ongoing meeting with two prep items one done shows 1/2 not done" {
  agenda "$(row 0000000000a1 "$(at 09:30)" "$(at 10:30)" Standup https://meet.google.com/abc-defg-hij)"
  todos "$(jq -nc --arg prep 0000000000a1 '{id: 1, text: "Standup · Baca catatan", done: true, created: 0, prep: $prep}')" \
        "$(jq -nc --arg prep 0000000000a1 '{id: 2, text: "Standup · Siapkan slide", done: false, created: 0, prep: $prep}')" \
        "$(jq -nc --arg prep 0000000000b2 '{id: 3, text: "Lain · Abaikan", done: false, created: 0, prep: $prep}')"
  shown
  [ "$(jq -c '[.meeting.prep, .meeting.prep_done]' <<< "$event")" = '["1/2",false]' ]
}

@test "an ongoing meeting with all prep items done shows 2/2 done" {
  agenda "$(row 0000000000a1 "$(at 09:30)" "$(at 10:30)" Standup)"
  todos "$(jq -nc --arg prep 0000000000a1 '{id: 1, text: "Standup · Baca catatan", done: true, created: 0, prep: $prep}')" \
        "$(jq -nc --arg prep 0000000000a1 '{id: 2, text: "Standup · Siapkan slide", done: true, created: 0, prep: $prep}')"
  shown
  [ "$(jq -c '[.meeting.prep, .meeting.prep_done]' <<< "$event")" = '["2/2",true]' ]
}

@test "an ongoing meeting with no prep items shows empty prep" {
  agenda "$(row 0000000000a1 "$(at 09:30)" "$(at 10:30)" Standup)"
  todos "$(item 1 Laporan "$(at 17:00)")"
  shown
  [ "$(jq -c '[.meeting.prep, .meeting.prep_done]' <<< "$event")" = '["",false]' ]
}
