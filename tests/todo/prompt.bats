# tests/todo/prompt.bats: adding items through rofi; deadlines open in the island picker.
load ../helpers
load common
bats_require_minimum_version 1.5.0

pin_clock() { export ISLAND_NOW=1792551600 TZ=Asia/Jakarta; } # Wed 2026-10-21 10:00
closed_before_rofi() {
  [ "$(grep -nm1 'close island-expanded' "$FIX/calls" | cut -d: -f1)" -lt "$(grep -nm1 '^rofi' "$FIX/calls" | cut -d: -f1)" ]
}

@test "prompt closes the card, asks rofi and adds the answer" {
  printf '  telepon ibu \n' > "$FIX/rofi_answers"
  start_listener
  run todo prompt
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["telepon ibu"]' ]
  closed_before_rofi
}

@test "cancelling the prompt adds nothing" {
  start_listener
  run todo prompt
  [ "$status" -eq 0 ]
  quiet 0.3
  [ ! -e "$DATA" ] || [ "$(jq -c '[.rows]' <<< "$event")" = '[[]]' ]
}

@test "prompt adds without a deadline, then opens the picker on the new item" {
  pin_clock
  printf '%s\n' 'Laporan Q3' > "$FIX/rofi_answers"
  start_listener
  run todo prompt
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["Laporan Q3"]' ]
  [ "$(jq -c .picker.show <<< "$event")" = 'false' ]
  next_event
  [ "$(jq -c '.items[0] | [.text, has("due")]' "$DATA")" = '["Laporan Q3",false]' ]
  [ "$(jq -c '[.picker.show,.picker.text,.picker.month_label,.picker.summary]' <<< "$event")" = '[true,"Laporan Q3","Oktober 2026","Rab 21 Okt · 17:00"]' ]
  grep -q '^eww update island_tab=tugas' "$FIX/calls"
}

@test "a cancelled picker after prompt leaves the new item without a deadline" {
  pin_clock
  printf '%s\n' 'Laporan Q3' > "$FIX/rofi_answers"
  start_listener
  run todo prompt
  [ "$status" -eq 0 ]
  next_event
  next_event
  [ "$(jq -c .picker.show <<< "$event")" = 'true' ]
  todo pick cancel; next_event
  [ "$(jq -c .picker.show <<< "$event")" = 'false' ]
  [ "$(jq -c '.items[0] | has("due")' "$DATA")" = 'false' ]
}
