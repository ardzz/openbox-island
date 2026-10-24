# tests/kalender/join.bats: joining a meeting from the tab.
load ../helpers
load common
bats_require_minimum_version 1.5.0

@test "join closes the card, then opens the row's meeting link" {
  agenda now later
  run kalender join 000000000001
  [ "$status" -eq 0 ]
  wait_for_call '^xdg-open https://meet.google.com/abc-defg-hij$'
  [ "$(grep -nm1 'close island-expanded' "$FIX/calls" | cut -d: -f1)" -lt "$(grep -nm1 '^xdg-open' "$FIX/calls" | cut -d: -f1)" ]
}

@test "join refuses unknown ids and links that are not plain https, before touching the card" {
  agenda now
  edit_agenda '.rows += [(.rows[0] | .id = "000000000009" | .join = "javascript:alert(1)"),
    (.rows[0] | .id = "000000000008" | .join = ""), (.rows[0] | .id = "000000000007" | .join = "https://a b")]'
  run kalender join 000000000002
  [ "$status" -eq 1 ]
  run kalender join 000000000009
  [ "$status" -eq 1 ]
  run kalender join 000000000008
  [ "$status" -eq 1 ]
  run kalender join 000000000007
  [ "$status" -eq 1 ]
  sleep 0.2
  [ ! -s "$FIX/calls" ]
}

@test "malformed ids and unknown commands are usage errors" {
  run kalender join 'x;rm -rf'
  [ "$status" -eq 2 ]
  run kalender join
  [ "$status" -eq 2 ]
  run kalender scroll left
  [ "$status" -eq 2 ]
  run kalender explode
  [ "$status" -eq 2 ]
}
