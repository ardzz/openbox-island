# tests/alert/capslock.bats
load helpers

set_led() {
  mkdir -p "$ISLAND_LEDS/$1"
  printf '%s\n' "$2" > "$ISLAND_LEDS/$1/brightness"
}

@test "caps lock is on when any keyboard LED is lit and emits only on change" {
  set_led input3::capslock 0
  set_led input7::capslock 0
  set_led input3::numlock 1
  {
    capslock_snapshot
    set_led input3::numlock 0; capslock_snapshot
    set_led input7::capslock 1; capslock_snapshot
    set_led input3::capslock 1; capslock_snapshot
    set_led input7::capslock 0; capslock_snapshot
    set_led input3::capslock 0; capslock_snapshot
    capslock_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["capslock","Caps Lock nyala","",-1,""],["capslock","Caps Lock mati","",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F0632|\U000F0632' ]
}

@test "caps lock already on at start is a silent baseline" {
  set_led input3::capslock 1
  {
    capslock_snapshot
    capslock_snapshot
    set_led input3::capslock 0; capslock_snapshot
  } > "$RESULT"
  [ "$(jq -sc 'map(.text)' "$RESULT")" = '["Caps Lock mati"]' ]
}
