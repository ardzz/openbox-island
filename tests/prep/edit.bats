# tests/prep/edit.bats: editing a meeting's prep items from rofi (scripts/prep edit).
load common
bats_require_minimum_version 1.5.0

# calls: the ordered log of fake eww and fake rofi calls.
calls() { cat "$FIX/calls"; }

@test "edit without a template asks with an empty filter and saves the answer as a new line" {
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'a; b'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly Report |  | a; b' ]
  # rofi: -p Prep, -mesg naming the title, empty -filter, -l 0.
  [[ $(calls) == *'rofi -dmenu -p Prep -mesg Item prep untuk Weekly Report; pisahkan dengan ; -filter  -l 0'* ]]
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
  [[ $(calls) == *'rofi -dmenu -p Prep -mesg Item prep untuk Weekly Report; pisahkan dengan ; -filter a; b -l 0'* ]]
  [ "$(cat "$ISLAND_PREP")" = 'Weekly Report |  | a' ]
}

@test "edit rewrites the first matching template line, keeping its sebelum" {
  prep_write 'Weekly | 1h | lama; lain'
  agenda_rows "$(row aaaaaaaaaaaa 'Weekly Report' "$(at '2026-10-22 09:00')")"
  answer 'baru'
  run "$SCRIPTS/prep" edit aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [[ $(calls) == *'-filter lama; lain -l 0'* ]]
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
  [[ $(calls) == *'-filter lama -l 0'* ]]
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
  [ "$(calls)" = $'eww update island_reveal=false\neww close island-expanded\nrofi -dmenu -p Prep -mesg Item prep untuk Weekly Report; pisahkan dengan ; -filter  -l 0' ]
}
