# tests/lib/store.bats
setup() {
  load ../helpers
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/store.sh"
  F="$BATS_TEST_TMPDIR/data/sub/list.json"
}

@test "store_read prints the default for a missing file" {
  run store_read "$F" '{"n":0}'
  [ "$status" -eq 0 ]
  [ "$output" = '{"n":0}' ]
}

@test "store_read prints the stored JSON" {
  mkdir -p "${F%/*}"; printf '{"n": 3}\n' > "$F"
  run store_read "$F" '{"n":0}'
  [ "$(jq -c . <<< "$output")" = '{"n":3}' ]
}

@test "store_read prints the default for invalid or empty files" {
  mkdir -p "${F%/*}"
  printf '{"n":' > "$F"
  run store_read "$F" '{"n":0}'; [ "$output" = '{"n":0}' ]
  : > "$F"
  run store_read "$F" '{"n":0}'; [ "$output" = '{"n":0}' ]
  printf '1\n2\n' > "$F"
  run store_read "$F" '{"n":0}'; [ "$output" = '{"n":0}' ]
}

@test "store_update creates the directory and applies the filter to the default" {
  run store_update "$F" '{"n":0}' '.n += $k' --argjson k 2
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$F")" = '{"n":2}' ]
}

@test "20 parallel updates all land and leave no temp files" {
  local i
  for i in $(seq 20); do store_update "$F" '{"n":0}' '.n += 1' & done
  wait
  [ "$(jq .n "$F")" = 20 ]
  run ls -A "${F%/*}"
  [ "$output" = $'list.json\nlist.json.lock' ]
}

@test "a corrupt file reads as the default and is moved aside on update" {
  mkdir -p "${F%/*}"; printf 'garbage' > "$F"
  run store_read "$F" '{"n":0}'
  [ "$output" = '{"n":0}' ]
  run store_update "$F" '{"n":0}' '.n += 1'
  [ "$status" -eq 0 ]
  [ "$(cat "$F.corrupt")" = garbage ]
  [ "$(jq -c . "$F")" = '{"n":1}' ]
}

@test "a failing filter returns non-zero and leaves the file untouched" {
  mkdir -p "${F%/*}"; printf '{"n":1}\n' > "$F"
  run store_update "$F" '{"n":0}' '.n | error("no")'
  [ "$status" -ne 0 ]
  run store_update "$F" '{"n":0}' '.n +'
  [ "$status" -ne 0 ]
  run store_update "$F" '{"n":0}' 'null'
  [ "$status" -ne 0 ]
  [ "$(cat "$F")" = '{"n":1}' ]
  run ls -A "${F%/*}"
  [ "$output" = $'list.json\nlist.json.lock' ]
}
