# tests/marquee.bats
setup() {
  load helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  ST="$XDG_RUNTIME_DIR/eww-island"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$ST" "$BIN"
  printf '#!/usr/bin/env bash\nprintf "10000\\n"\n' > "$BIN/date"
  chmod +x "$BIN/date"
  PATH="$BIN:$PATH"
  title=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn
  artist=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrst
  jq -nc --arg title "$title" --arg artist "$artist" '{title:$title,artist:$artist}' > "$ST/media.json"
}
tick() { echo $(( 10000 - $1 * 2 )) > "$ST/marquee_at"; }

@test "short strings stay static and newlines become spaces" {
  printf '{"title":"Short\\ntitle","artist":"Artis é"}\n' > "$ST/media.json"
  tick 80
  run "$SCRIPTS/marquee"
  [ "$status" -eq 0 ]
  [ "$output" = '{"title":"Short title","artist":"Artis é"}' ]
}

@test "title holds for six ticks then advances and loops through the separator" {
  for t in {0..6}; do
    tick "$t"
    run "$SCRIPTS/marquee"
    [ "$status" -eq 0 ]
    [ "$(jq -r .title <<<"$output")" = ABCDEFGHIJKLMNOPQRSTUVWXYZabcd ]
  done
  tick 7
  run "$SCRIPTS/marquee"
  [ "$(jq -r .title <<<"$output")" = BCDEFGHIJKLMNOPQRSTUVWXYZabcde ]
  tick 45
  run "$SCRIPTS/marquee"
  [ "$(jq -r .title <<<"$output")" = 'n   ·   ABCDEFGHIJKLMNOPQRSTUV' ]
  tick 53
  run "$SCRIPTS/marquee"
  [ "$(jq -r .title <<<"$output")" = ABCDEFGHIJKLMNOPQRSTUVWXYZabcd ]
}

@test "non-ASCII windows count characters rather than bytes" {
  printf '{"title":"é世界ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn","artist":"A"}\n' > "$ST/media.json"
  tick 7
  run "$SCRIPTS/marquee"
  [ "$status" -eq 0 ]
  [ "$(jq -r .title <<<"$output")" = 世界ABCDEFGHIJKLMNOPQRSTUVWXYZab ]
  [ "$(jq '.title|length' <<<"$output")" -eq 30 ]
}

@test "artist scrolls independently at width 36 while short title stays static" {
  jq '.title="Short"' "$ST/media.json" > "$ST/input"
  mv "$ST/input" "$ST/media.json"
  tick 7
  run "$SCRIPTS/marquee"
  [ "$status" -eq 0 ]
  [ "$output" = '{"title":"Short","artist":"BCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijk"}' ]
  tick 59
  run "$SCRIPTS/marquee"
  [ "$(jq -r .artist <<<"$output")" = ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij ]
}

@test "missing or invalid media yields empty strings" {
  rm "$ST/media.json"
  run "$SCRIPTS/marquee"
  [ "$status" -eq 0 ]
  [ "$output" = '{"title":"","artist":""}' ]
  for invalid in '{' '{}' 'null' '{"title":4,"artist":"A"}'; do
    printf '%s\n' "$invalid" > "$ST/media.json"
    run "$SCRIPTS/marquee"
    [ "$status" -eq 0 ]
    [ "$output" = '{"title":"","artist":""}' ]
  done
}

@test "missing garbage or future start time uses the beginning" {
  run "$SCRIPTS/marquee"
  [ "$status" -eq 0 ]
  [ "$(jq -r .title <<<"$output")" = ABCDEFGHIJKLMNOPQRSTUVWXYZabcd ]
  for start in garbage -1 10002; do
    echo "$start" > "$ST/marquee_at"
    run "$SCRIPTS/marquee"
    [ "$status" -eq 0 ]
    [ "$(jq -r .title <<<"$output")" = ABCDEFGHIJKLMNOPQRSTUVWXYZabcd ]
  done
}
