# tests/todo/due-view.bats: deadline order and chips in the Tugas tab.
load ../helpers
load common
bats_require_minimum_version 1.5.0

pin_clock() { export ISLAND_NOW=1792551600 TZ=Asia/Jakarta; } # Wed 2026-10-21 10:00
chips() { jq -c '[.rows[] | [.text,.due_label,.due_class]]' <<< "$event"; }

@test "open items with a deadline come first, soonest first, then the rest newest first" {
  pin_clock
  todo add tanpa1
  todo add jauh --due 1793181600
  todo add dekat --due 1792576800
  todo add tanpa2
  todo add selesai --due 1792566000
  start_listener
  todo toggle "$(id_of selesai)"; next_event
  [ "$(texts)" = '["dekat","jauh","tanpa2","tanpa1"]' ]
  [ "$(jq -c '[.open,.more]' <<< "$event")" = '[4,1]' ]
}

@test "chips read as a time today, besok, a weekday, or a date; under a day is soon" {
  pin_clock
  todo add a --due 1792566000
  todo add b --due 1792634400
  todo add c --due 1792749600
  todo add d --due 1793613600
  start_listener
  [ "$(chips)" = '[["a","14:00","due-soon"],["b","besok 09:00","due-soon"],["c","Jum 17:00",""],["d","2 Nov",""]]' ]
}

@test "a passed deadline reads terlambat; done items and items without one show no chip" {
  pin_clock
  todo add lewat --due 1792548000
  todo add bebas
  todo add beres --due 1792576800
  start_listener
  todo toggle "$(id_of beres)"; next_event
  [ "$(chips)" = '[["lewat","terlambat","due-late"],["bebas","",""],["beres","",""]]' ]
}

@test "while a deadline is open the chips refresh on their own as time passes" {
  export TZ=Asia/Jakarta ISLAND_TODO_TICK=0.2
  todo add a --due $((EPOCHSECONDS + 2))
  start_listener
  [ "$(jq -r '.rows[0].due_label' <<< "$event")" != terlambat ]
  next_event 4
  [ "$(jq -r '.rows[0].due_label' <<< "$event")" = terlambat ]
}
