# tests/todo/prompt.bats: adding items and deadlines through rofi.
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

@test "prompt then asks for a deadline, offering none first, and stores both" {
  pin_clock
  printf '%s\n' 'Laporan Q3' 'Jumat 17:00' > "$FIX/rofi_answers"
  run todo prompt
  [ "$status" -eq 0 ]
  [ "$(jq -c '.items[0] | [.text,.due]' "$DATA")" = '["Laporan Q3",1792749600]' ]
  grep -q '^menu Tanpa deadline|' "$FIX/calls"
}

@test "choosing no deadline, or cancelling that step, keeps the item without one" {
  pin_clock
  printf '%s\n' a 'Tanpa deadline' b > "$FIX/rofi_answers"
  todo prompt
  todo prompt
  [ "$(jq -c '[.items[] | [.text, has("due")]]' "$DATA")" = '[["a",false],["b",false]]' ]
}

@test "an unreadable deadline keeps the item without one and says so" {
  pin_clock
  printf '%s\n' a 'kapan-kapan' > "$FIX/rofi_answers"
  run todo prompt
  [ "$(jq -c '[.items[] | [.text, has("due")]]' "$DATA")" = '[["a",false]]' ]
  grep -q '^notify-send .*\[kapan-kapan\]' "$FIX/calls"
}

@test "due closes the card, then sets or clears the deadline from rofi" {
  pin_clock
  todo add a
  start_listener
  printf 'besok 14:00\n' > "$FIX/rofi_answers"
  run todo due "$(id_of a)"
  [ "$status" -eq 0 ]
  next_event
  [ "$(jq -c '.items[0].due' "$DATA")" = '1792652400' ]
  grep -q '^menu Hapus deadline|' "$FIX/calls"
  closed_before_rofi
  printf 'Hapus deadline\n' > "$FIX/rofi_answers"
  todo due "$(id_of a)"; next_event
  [ "$(jq -c '.items[0] | has("due")' "$DATA")" = 'false' ]
}

@test "due keeps the deadline on cancel or unreadable answers and rejects unknown ids before asking" {
  pin_clock
  todo add a --due 1793181600
  run todo due 1
  [ "$status" -eq 0 ]
  printf 'kapan-kapan\n' > "$FIX/rofi_answers"
  run todo due 1
  [ "$status" -eq 1 ]
  grep -q '^notify-send .*\[kapan-kapan\]' "$FIX/calls"
  [ "$(jq -c '.items[0].due' "$DATA")" = '1793181600' ]
  : > "$FIX/calls"
  run todo due 999
  [ "$status" -eq 1 ]
  ! grep -q '^rofi' "$FIX/calls"
  run todo due x
  [ "$status" -eq 2 ]
}
