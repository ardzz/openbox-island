# tests/alert/audio.bats
load helpers

@test "volume changes use the first channel percent and the low mid high boundaries" {
  {
    audio_update 10 no no
    audio_update 33 no no
    audio_update 34 no no
    audio_update 66 no no
    audio_update 67 no no
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["volume","Volume","33%",33],["volume","Volume","34%",34],["volume","Volume","66%",66],["volume","Volume","67%",67]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\uF026|\uF027|\uF027|\uF028' ]
}

@test "sink mute changes emit Bisu even when the volume is unchanged" {
  {
    audio_update 42 no no
    audio_update 42 yes no
    audio_update 42 yes no
    audio_update 42 no no
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["volume","Bisu","42%",42],["volume","Volume","42%",42]]' ]
  [ "$(jq -sr '.[0].icon' "$RESULT")" = $'\U000F0581' ]
}

@test "source mute changes emit microphone state with no percentage" {
  {
    audio_update 42 no no
    audio_update 42 no yes
    audio_update 42 no yes
    audio_update 42 no no
  } > "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level])' "$RESULT")" = '[["mic","Mikrofon mati","",-1],["mic","Mikrofon nyala","",-1]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F036D|\U000F036C' ]
}

@test "audio client card and stream noise never triggers another query" {
  make_fakes
  audio_snapshot > "$RESULT"
  before=$(cat "$ALERT_FIXTURE/audio-queries")
  {
    audio_event "Event 'new' on client #10987"
    audio_event "Event 'change' on card #54"
    audio_event "Event 'change' on sink-input #65"
    audio_event "Event 'change' on source-output #66"
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$(cat "$ALERT_FIXTURE/audio-queries")" = "$before" ]
  printf '51\n' > "$ALERT_FIXTURE/volume"
  audio_event "Event 'change' on sink #65" >> "$RESULT"
  [ "$(jq -c '[.kind,.value,.level]' "$RESULT")" = '["volume","51%",51]' ]
}
