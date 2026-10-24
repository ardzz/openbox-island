# tests/prep/edit.bats: editing a meeting's prep items from rofi (scripts/prep edit).
load common
bats_require_minimum_version 1.5.0

# calls: the ordered log of fake eww and fake rofi calls.
calls() { cat "$FIX/calls"; }

# rofi_args: the argv elements of the (last) rofi call, one per line.
rofi_args() {
  calls | awk '/^rofi$/{last=NR} {lines[NR]=$0} END { for (i=last+1; i<=NR; i++) print lines[i] }'
}

# filter_arg: the argument after -filter on stdin (keeps a leading space visible).
filter_arg() {
  local line prev=''
  while IFS= read -r line; do
    if [[ $prev == -filter ]]; then printf '%s' "$line"; return 0; fi
    prev=$line
  done
}

@test "edit without a template asks with an empty filter and saves the answer as a new line" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'a; b'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly Report |  | a; b' ]
  [ "$(rofi_args)" = $'-dmenu\n-p\nPrep\n-mesg\nItem prep untuk Weekly Report; pisahkan dengan ;\n-filter\n\n-l\n0' ]
}

@test "edit creates the items when the meeting is within 24h" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'Report progres; Plan minggu depan'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.items[].text]' "$TODO_FILE")" = '["Weekly Report · Report progres","Weekly Report · Plan minggu depan"]' ]
  [ "$(jq -c '[.items[].prep]' "$TODO_FILE")" = '["aaaaaaaaaaaa","aaaaaaaaaaaa"]' ]
  [ "$(cat "$PREP_LEDGER")" = "aaaaaaaaaaaa $(at '2026-10-22 09:00')" ]
}

@test "edit again prefills the current items and rewrites the line" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'a; b'
  "$SCRIPTS/prep" edit aaaaaaaaaaaa
  answer 'a'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(rofi_args | filter_arg)" = 'a; b' ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly Report |  | a' ]
}

@test "edit rewrites the first matching template line, keeping its sebelum" {
  prep_write 'Weekly | 1h | lama; lain'
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'baru'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(rofi_args | filter_arg)" = 'lama; lain' ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly | 1h | baru' ]
  [ "$(jq -c '[.items[].text]' "$TODO_FILE")" = '["Weekly Report · baru"]' ]
  [ "$(jq -c '[.items[].due]' "$TODO_FILE")" = "[$(at '2026-10-21 17:00')]" ]
}

@test "an empty answer removes the matching line" {
  prep_write '# header' 'Weekly | 1h | lama' 'Standup | 30m | Cek blokir'
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer ''
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(rofi_args | filter_arg)" = 'lama' ]
  [ "$(cat "$ISLAND_PREP")" = $'# header\nStandup | 30m | Cek blokir' ]
  [ ! -e "$TODO_FILE" ]
}

@test "cancelling rofi changes nothing" {
  prep_write 'Weekly | 1h | lama'
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  # No answer queued: the fake rofi cancels.
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly | 1h | lama' ]
  [ ! -e "$TODO_FILE" ]
  [ ! -e "$PREP_LEDGER" ]
}

@test "cancelling rofi without a template creates no file" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ ! -e "$ISLAND_PREP" ]
  [ ! -e "$TODO_FILE" ]
}

@test "an unknown id fails with prep: acara tidak ditemukan and never asks rofi" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'a; b'
  run --separate-stderr "$SCRIPTS/prep" edit bbbbbbbbbbbb
  [ "$status" -eq 1 ]
  [ "$stderr" = 'prep: acara tidak ditemukan' ]
  [ -z "$(calls)" ]
  [ ! -e "$ISLAND_PREP" ]
}

@test "a missing or not-ok agenda is also an unknown id" {
  answer 'a; b'
  run --separate-stderr "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 1 ]
  [ "$stderr" = 'prep: acara tidak ditemukan' ]
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")" false
  run --separate-stderr "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 1 ]
  [ "$stderr" = 'prep: acara tidak ditemukan' ]
  [ -z "$(calls)" ]
}

@test "a bad id or an unknown command is a usage error" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'a; b'
  run "$SCRIPTS/prep" edit xyz
  [ "$status" -eq 2 ]
  run "$SCRIPTS/prep" edit AAAAAAAAAAAA
  [ "$status" -eq 2 ]
  run "$SCRIPTS/prep" edit aaaaaaaaaaa
  [ "$status" -eq 2 ]
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa extra
  [ "$status" -eq 2 ]
  run "$SCRIPTS/prep" explode
  [ "$status" -eq 2 ]
  run "$SCRIPTS/prep"
  [ "$status" -eq 2 ]
  [ -z "$(calls)" ]
  [ ! -e "$ISLAND_PREP" ]
}

@test "island dismiss happens before rofi" {
  expanded_card
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'a; b'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(calls)" = $'eww update island_reveal=false\neww close island-expanded\nrofi\n-dmenu\n-p\nPrep\n-mesg\nItem prep untuk Weekly Report; pisahkan dengan ;\n-filter\n\n-l\n0' ]
}

@test "an answer over twenty items saves twenty and notifies" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer "$(many_items 21)"
  run --separate-stderr "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$stderr" = 'prep: maksimal 20 item, sisanya dibuang' ]
  [ "$(prep_templates | jq '.[0].items | length')" -eq 20 ]
  [ "$(jq '.items | length' "$TODO_FILE")" -eq 20 ]
  [[ $(calls) == *'notify-send [-a] [Kalender] [--] [Prep: maksimal 20 item] [Sisanya dibuang]'* ]]
}

@test "the title is escaped for markup only inside the message" {
  agenda_rows "$(row aaaaaaaaaaaa 'R&D <draft>' "$(at '2026-10-22 09:00')")"
  answer 'a'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  local args; args=$(rofi_args)
  [[ $args == *$'\n-mesg\nItem prep untuk R&amp;D &lt;draft&gt;; pisahkan dengan ;\n-filter\n'* ]]
  [ "$(cat "$ISLAND_PREP")" = 'R&D <draft> |  | a' ]
}

@test "a prefill starting with a dash can never be a rofi option" {
  prep_write 'Weekly | 2j | -no-custom'
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  # No answer queued: cancel must leave the template intact.
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(rofi_args | filter_arg)" = ' -no-custom' ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly | 2j | -no-custom' ]
  [ ! -e "$TODO_FILE" ]
}
