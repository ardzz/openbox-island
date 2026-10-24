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
  # The add and the picker-open can land in one emit or two (request race).
  next_event
  [ "$(texts)" = '["Laporan Q3"]' ]
  if [ "$(jq -c .picker.show <<< "$event")" != 'true' ]; then next_event; fi
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
  # The add and the picker-open can land in one emit or two (request race).
  next_event
  if [ "$(jq -c .picker.show <<< "$event")" != 'true' ]; then next_event; fi
  [ "$(jq -c .picker.show <<< "$event")" = 'true' ]
  todo pick cancel; next_event
  [ "$(jq -c .picker.show <<< "$event")" = 'false' ]
  [ "$(jq -c '.items[0] | has("due")' "$DATA")" = 'false' ]
}

@test "prompt with no listener running records a request the next listener opens" {
  pin_clock
  printf '%s\n' 'Laporan Q3' > "$FIX/rofi_answers"
  # No start_listener: prompt dismisses the card, so its card-only listener is
  # stopped; only the recorded request can open the picker on the next start.
  run todo prompt
  [ "$status" -eq 0 ]
  [ ! -p "$FIFO" ]
  local id; id=$(jq -r '.items[0].id' "$DATA")
  [ "$(jq -c '.items[0] | [.text, has("due")]' "$DATA")" = '["Laporan Q3",false]' ]
  [ "$(cat "$ST/todo-pick")" = "$id" ]
  grep -q '^eww update island_tab=tugas' "$FIX/calls"
  start_listener
  [ "$(jq -c '[.picker.show,.picker.text,.picker.summary]' <<< "$event")" = '[true,"Laporan Q3","Rab 21 Okt · 17:00"]' ]
}

@test "prompt opens the picker on its own item when another add lands first" {
  pin_clock
  printf '%s\n' 'milik prompt' > "$FIX/rofi_answers"
  start_listener
  # The fake rofi adds a competing item while the prompt is being answered,
  # so an id read before the prompt's own add would point at the wrong task.
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "rofi %s\n" "$*" >> "$FIX/calls"' \
    'menu=$(cat); [[ -z $menu ]] || printf "menu %s\n" "${menu//$"\n"/|}" >> "$FIX/calls"' \
    "\"$SCRIPTS/todo\" add penyusup" \
    '[[ -s $FIX/rofi_answers ]] || exit 1' \
    'head -n 1 "$FIX/rofi_answers"; sed -i 1d "$FIX/rofi_answers"' > "$BIN/rofi"
  chmod +x "$BIN/rofi"
  run todo prompt
  [ "$status" -eq 0 ]
  local prompt_id; prompt_id=$(jq -r '.items[] | select(.text == "milik prompt") | .id' "$DATA")
  local other_id; other_id=$(jq -r '.items[] | select(.text == "penyusup") | .id' "$DATA")
  [ "$prompt_id" != "$other_id" ]
  [ "$(cat "$ST/todo-pick")" = "$prompt_id" ]
}
