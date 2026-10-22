# tests/alert/brightness.bats
load helpers

@test "brightness truncates decimals and ignores changes within the same integer percent" {
  {
    brightness_update 17.00
    brightness_update 17.99
    brightness_update 33.99
    brightness_update 34.01
    brightness_update 67.90
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["brightness","Kecerahan","33%",33],["brightness","Kecerahan","34%",34],["brightness","Kecerahan","67%",67]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F00DE|\U000F00DF|\U000F00E0' ]
}
