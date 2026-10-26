load ../helpers

setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export OUTPUT_FIXTURE="$BATS_TEST_TMPDIR/sinks.json"
  export OUTPUT_DEFAULT="$BATS_TEST_TMPDIR/default"
  export OUTPUT_MUTATIONS="$BATS_TEST_TMPDIR/mutations"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  printf '%s\n' '[{"name":"alsa_output.speaker","description":"  Speakers  "},{"name":"bluez_output.headset.1","description":"WH-1000XM4"},{"name":"alsa_output.hdmi","description":"  "}]' > "$OUTPUT_FIXTURE"
  echo bluez_output.headset.1 > "$OUTPUT_DEFAULT"
  touch "$OUTPUT_MUTATIONS"
  cat > "$BATS_TEST_TMPDIR/bin/pactl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  '--format=json list sinks') cat "$OUTPUT_FIXTURE" ;;
  get-default-sink) cat "$OUTPUT_DEFAULT" ;;
  '--format=json list sink-inputs') echo '[{"index":17},{"index":42}]' ;;
  'set-default-sink '*|'move-sink-input '*)
    printf '%s\n' "$*" >> "$OUTPUT_MUTATIONS"
    if [[ ${OUTPUT_FAIL_FIRST_MOVE:-0} == 1 && $1 == move-sink-input && $2 == 17 ]]; then exit 1; fi ;;
  subscribe)
    echo "Event 'change' on sink-input #17"
    sleep 0.15
    echo alsa_output.speaker > "$OUTPUT_DEFAULT"
    echo "Event 'change' on server #0"
    echo "Event 'change' on sink #1"
    sleep 5 ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/pactl"
}

@test "render returns sink names, trimmed descriptions and active-first label order" {
  run bash -c 'source "$1"; render' _ "$SCRIPTS/outputs"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"name":"bluez_output.headset.1","label":"WH-1000XM4","active":true},{"name":"alsa_output.speaker","label":"Speakers","active":false},{"name":"alsa_output.hdmi","label":"alsa_output.hdmi","active":false}]' ]
}

@test "set changes the default then moves every active sink input without volume changes" {
  run "$SCRIPTS/outputs" set alsa_output.speaker
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_MUTATIONS")" = $'set-default-sink alsa_output.speaker\nmove-sink-input 17 alsa_output.speaker\nmove-sink-input 42 alsa_output.speaker' ]
}

@test "unknown sinks fail without any mutations" {
  run "$SCRIPTS/outputs" set missing
  [ "$status" -eq 1 ]
  [ ! -s "$OUTPUT_MUTATIONS" ]
}

@test "subscribe emits changed sink state once and ignores sink-input events" {
  run timeout 0.8 "$SCRIPTS/outputs"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(jq -r '.[0].name' <<<"${lines[0]}")" = bluez_output.headset.1 ]
  [ "$(jq -r '.[0].name' <<<"${lines[1]}")" = alsa_output.speaker ]
}

@test "a vanished first sink input does not prevent moving the remaining inputs" {
  export OUTPUT_FAIL_FIRST_MOVE=1
  run "$SCRIPTS/outputs" set alsa_output.speaker
  [ "$status" -ne 0 ]
  [ "$(cat "$OUTPUT_MUTATIONS")" = $'set-default-sink alsa_output.speaker\nmove-sink-input 17 alsa_output.speaker\nmove-sink-input 42 alsa_output.speaker' ]
}

@test "set-index resolves the current sorted list and passes apostrophes as literal argv" {
  printf '%s\n' '[{"name":"speaker'\''; false; #","description":"Speakers"},{"name":"bluez_output.headset.1","description":"WH-1000XM4"}]' > "$OUTPUT_FIXTURE"
  run "$SCRIPTS/outputs" set-index 1
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_MUTATIONS")" = $'set-default-sink speaker\'; false; #\nmove-sink-input 17 speaker\'; false; #\nmove-sink-input 42 speaker\'; false; #' ]
}

@test "set-index rejects out-of-range and malformed indices without mutations" {
  for index in 3 -1 invalid '0; false' ''; do
    run "$SCRIPTS/outputs" set-index "$index"
    [ "$status" -eq 1 ]
    [ ! -s "$OUTPUT_MUTATIONS" ]
  done
}

@test "output widget invokes numeric selection rather than interpolating sink names" {
  local widget
  widget=$(<"$REPO/eww/yuck/tabs/musik.yuck")
  [[ $widget == *'scripts/outputs set-index ${row.key}'* ]]
  [[ $widget != *'${row.name}'* ]]
}
