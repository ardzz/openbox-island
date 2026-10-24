# tests/upcoming/deadline.bats: the deadline part and the empty state of the left pill.
load ../helpers
load common

@test "the earliest open deadline shows with the Tugas chip label" {
  todos "$(item 1 Laporan "$(at 17:00 2)")" "$(item 2 Slide "$(at 17:00 1)")" \
    "$(item 3 Selesai "$(at 12:00)" true)" "$(item 4 'Tanpa deadline')"
  shown
  [ "$(jq -c .deadline <<< "$event")" = '{"show":true,"title":"Slide","label":"besok 17:00","class":"","more":0}' ]
}

@test "an overdue deadline comes first and +N counts the others due within 24 hours" {
  todos "$(item 1 Revisi "$(at 09:00)")" "$(item 2 Laporan "$(at 17:00)")" \
    "$(item 3 Slide "$(at 09:00 1)")" "$(item 4 Proposal "$(at 17:00 2)")"
  shown
  [ "$(d title) | $(d label) | $(d class) | $(d more)" = 'Revisi | terlambat | due-late | 2' ]
}

@test "a deadline later today is due-soon with its time" {
  todos "$(item 1 Laporan "$(at 17:00)")"
  shown
  [ "$(d label) $(d class)" = '17:00 due-soon' ]
}

@test "nothing to show is the empty state" {
  todos "$(item 1 'Tanpa deadline')" "$(item 2 Selesai "$(at 17:00)" true)"
  shown
  [ "$(d show) $(m show) $(jq -r .empty <<< "$event")" = 'false false true' ]
  agenda "$(row 0000000000a1 "$(at 14:00)" "$(at 15:00)" Demo)"
  shown
  [ "$(jq -r .empty <<< "$event")" = false ]
}

@test "a corrupt list hides the deadline and keeps the meeting" {
  printf 'not json\n' > "$DATA"
  agenda "$(row 0000000000a1 "$(at 14:00)" "$(at 15:00)" Demo)"
  shown
  [ "$(d show) $(m show)" = 'false true' ]
}

@test "a changed list shows within a tick" {
  start_listener
  [ "$(d show)" = false ]
  todos "$(item 1 Laporan "$(at 17:00)")"
  next_event 2
  [ "$(d title)" = Laporan ]
}
