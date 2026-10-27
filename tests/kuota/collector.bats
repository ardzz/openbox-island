load ../helpers

setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" TZ=UTC ISLAND_NOW=1000000
  export ISLAND_KUOTA_INTERVAL=300
  export HOME="$BATS_TEST_TMPDIR/home"
  unset OB_OMP
  unset ISLAND_KUOTA_SKIP
  export OMP_FIXTURE="$BATS_TEST_TMPDIR/response" OMP_STATUS="$BATS_TEST_TMPDIR/status"
  export KUOTA_TEST="$BATS_TEST_TMPDIR"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  ORIGINAL_PATH=$PATH
  local tool
  for tool in bash cat chmod dirname jq date mkdir mktemp mv rm; do
    ln -s "$(command -v "$tool")" "$BIN/$tool"
  done
  SETSID=$(command -v setsid)
  cat > "$BIN/omp" <<'EOF'
#!/usr/bin/env bash
[[ $* == 'usage --json --redact --no-extensions' ]] || exit 2
printf 'call\n' >> "$KUOTA_TEST/omp-calls"
read -r status < "$OMP_STATUS"
(( status == 0 )) || exit "$status"
cat "$OMP_FIXTURE"
EOF
  cat > "$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$KUOTA_TEST/sleeps"
IFS= read -r _ < "$KUOTA_TEST/ticks"
EOF
  chmod +x "$BIN/omp" "$BIN/sleep"
  printf '0\n' > "$OMP_STATUS"
  cat > "$OMP_FIXTURE" <<'EOF'
{"generatedAt":1000000000,"reports":[{"provider":"openai-codex","metadata":{"planType":"pro"},"limits":[{"label":"7 days","amount":{"used":34,"unit":"percent"},"window":{"resetsAt":1432000000}}]},{"provider":"anthropic","metadata":{},"limits":[{"label":"Claude 5 Hour","amount":{"used":12,"unit":"percent"},"window":{"resetsAt":1003900000}},{"label":"Claude 7 Day (Fable)","amount":{"used":2,"unit":"percent"},"window":{"resetsAt":1007200000}}]},{"provider":"anthropic","limits":[{"label":"5 Hour","amount":{"used":3,"unit":"percent"},"window":{"resetsAt":null}}]},{"provider":"github-copilot","limits":[{"label":"Premium Requests","amount":{"used":null,"unit":"requests"},"window":{"resetsAt":null}}]},{"provider":"google-antigravity","limits":[]}],"accountsWithoutUsage":[],"disabledCredentials":[]}
EOF
  mkfifo "$KUOTA_TEST/output" "$KUOTA_TEST/ticks" "$KUOTA_TEST/sleeps"
  exec {output_fd}<> "$KUOTA_TEST/output"
  exec {tick_fd}<> "$KUOTA_TEST/ticks"
  exec {sleep_fd}<> "$KUOTA_TEST/sleeps"
  export PATH="$BIN"
  STATE="$XDG_RUNTIME_DIR/eww-island/kuota.json"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  if [[ -n ${listener_pid:-} ]]; then
    kill -TERM -- "-$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
  exec {output_fd}>&-
  exec {tick_fd}>&-
  exec {sleep_fd}>&-
}

start_kuota() {
  [ -x "$SCRIPTS/kuota" ]
  "$SETSID" "$SCRIPTS/kuota" > "$KUOTA_TEST/output" 2> "$KUOTA_TEST/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" event
}

next_fetch() {
  IFS= read -r -t 2 -u "$sleep_fd" delay
  printf 'tick\n' >&"$tick_fd"
  IFS= read -r -t 2 -u "$sleep_fd" delay
}

@test "normalizes omp accounts in report order and caches the complete render" {
  start_kuota
  expected='{"ok":true,"updated":"13:46","note":"","accounts":[{"provider":"Codex","plan":"pro","limits":[{"label":"7 hari","used":34,"reset":"5 hr"}]},{"provider":"Claude","plan":"","limits":[{"label":"5 jam","used":12,"reset":"1j 5m"},{"label":"7 hari (Fable)","used":2,"reset":"2j"}]},{"provider":"Claude","plan":"","limits":[{"label":"5 jam","used":3,"reset":"—"}]},{"provider":"Copilot","plan":"","limits":[{"label":"Permintaan premium","used":-1,"reset":"—"}]}]}'
  [ "$(jq -S 'del(.fetched)' <<< "$event")" = "$(jq -S . <<< "$expected")" ]
  [ "$(jq -r '.fetched' <<< "$event")" = "$ISLAND_NOW" ]
  [ "$(cat "$STATE")" = "$event" ]
}

@test "empty skip list includes Antigravity and comma list skips exact providers" {
  export ISLAND_KUOTA_SKIP=''
  start_kuota
  [ "$(jq -r '.accounts[-1].provider' <<< "$event")" = Antigravity ]
}

@test "custom comma skip list replaces the default" {
  export ISLAND_KUOTA_SKIP='anthropic,openai-codex'
  start_kuota
  [ "$(jq -c '[.accounts[].provider]' <<< "$event")" = '["Copilot","Antigravity"]' ]
}

@test "non-percent and non-numeric amounts are unlimited with null resets" {
  printf '%s\n' '{"reports":[{"provider":"other","limits":[{"label":"2 Hours","amount":{"used":10,"unit":"requests"}},{"label":"1 Day","amount":{"used":"unknown","unit":"percent"}},{"label":"5 Hour","amount":{"used":null,"unit":"percent"}}]}]}' > "$OMP_FIXTURE"
  start_kuota
  [ "$(jq -c '.accounts[0]' <<< "$event")" = '{"provider":"other","plan":"","limits":[{"label":"2 jam","used":-1,"reset":"—"},{"label":"1 hari","used":-1,"reset":"—"},{"label":"5 jam","used":-1,"reset":"—"}]}' ]
}

@test "reset countdown handles minutes and past-due windows" {
  printf '%s\n' '{"reports":[{"provider":"anthropic","limits":[{"label":"5 Hour","amount":{"used":0,"unit":"percent"},"window":{"resetsAt":1002700000}},{"label":"7 Day","amount":{"used":100,"unit":"percent"},"window":{"resetsAt":1000000000}}]}]}' > "$OMP_FIXTURE"
  start_kuota
  [ "$(jq -c '[.accounts[0].limits[].reset]' <<< "$event")" = '["45m","segera"]' ]
}

@test "fetch failure before success emits an error once without a cache" {
  printf '1\n' > "$OMP_STATUS"
  start_kuota
  [ "$(jq -c . <<< "$event")" = '{"ok":false,"updated":"","note":"gagal memuat kuota","accounts":[]}' ]
  [ ! -f "$STATE" ]
  next_fetch
  ! IFS= read -r -t 0.1 -u "$output_fd" event
}

@test "invalid JSON is a fetch failure" {
  printf 'not json\n' > "$OMP_FIXTURE"
  start_kuota
  [ "$(jq -r '.note' <<< "$event")" = 'gagal memuat kuota' ]
  [ ! -f "$STATE" ]
}

@test "failed refresh retains the last good emission and cache" {
  start_kuota
  good=$event
  printf '1\n' > "$OMP_STATUS"
  next_fetch
  [ "$(cat "$STATE")" = "$good" ]
  ! IFS= read -r -t 0.1 -u "$output_fd" event
  printf '0\n' > "$OMP_STATUS"
  printf '{"reports":[]}\n' > "$OMP_FIXTURE"
  printf 'tick\n' >&"$tick_fd"
  IFS= read -r -t 2 -u "$output_fd" event
  [ "$(jq -c '.accounts' <<< "$event")" = '[]' ]
}

@test "missing omp reports the missing command" {
  rm "$BIN/omp"
  start_kuota
  [ "$(jq -r '.note' <<< "$event")" = 'omp tidak ditemukan' ]
  [ ! -f "$STATE" ]
}

@test "invalid polling interval uses the default" {
  export ISLAND_KUOTA_INTERVAL=invalid
  start_kuota
  IFS= read -r -t 2 -u "$sleep_fd" delay
  [ "$delay" = 300 ]
}

@test "finds omp in the default Bun bin directory outside PATH" {
  mkdir -p "$HOME/.bun/bin"
  mv "$BIN/omp" "$HOME/.bun/bin/omp"
  start_kuota
  [ "$(jq -r '.ok' <<< "$event")" = true ]
}

@test "OB_OMP overrides the command found on PATH" {
  export OB_OMP="$BATS_TEST_TMPDIR/custom-omp"
  mv "$BIN/omp" "$OB_OMP"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/omp"
  chmod +x "$BIN/omp"
  start_kuota
  [ "$(jq -r '.ok' <<< "$event")" = true ]
}

@test "reopening with a legacy successful cache preserves it when refresh fails" {
  mkdir -p "${STATE%/*}"
  good='{"ok":true,"updated":"12:00","note":"","accounts":[{"provider":"Codex","plan":"pro","limits":[]}]}'
  printf '%s\n' "$good" > "$STATE"
  printf '1\n' > "$OMP_STATUS"
  start_kuota
  [ "$event" = "$good" ]
  IFS= read -r -t 2 -u "$sleep_fd" delay
  [ -f "$KUOTA_TEST/omp-calls" ]
  [ "$(cat "$STATE")" = "$good" ]
  ! IFS= read -r -t 0.1 -u "$output_fd" event
}

@test "fresh successful cache emits immediately and waits until its next interval" {
  mkdir -p "${STATE%/*}"
  good='{"ok":true,"updated":"13:46","fetched":1000000,"note":"","accounts":[]}'
  printf '%s\n' "$good" > "$STATE"
  start_kuota
  [ "$event" = "$good" ]
  IFS= read -r -t 2 -u "$sleep_fd" delay
  [ "$delay" = 300 ]
  [ ! -f "$KUOTA_TEST/omp-calls" ]
  printf 'tick\n' >&"$tick_fd"
  IFS= read -r -t 2 -u "$output_fd" event
  [ -f "$KUOTA_TEST/omp-calls" ]
  [ "$(jq -r '.accounts[0].provider' <<< "$event")" = Codex ]
}

@test "fallback omp can resolve its Bun runtime outside PATH" {
  mkdir -p "$HOME/.bun/bin"
  rm "$BIN/omp"
  printf '#!/usr/bin/env bun\ncat "$OMP_FIXTURE"\n' > "$HOME/.bun/bin/omp"
  printf '#!/usr/bin/env bash\nexec bash "$@"\n' > "$HOME/.bun/bin/bun"
  chmod +x "$HOME/.bun/bin/omp" "$HOME/.bun/bin/bun"
  start_kuota
  [ "$(jq -r '.ok' <<< "$event")" = true ]
}
