# tests/lib/core.bats
setup() { load ../helpers; source "$SCRIPTS/lib/core.sh"; }

@test "fmt_time uses m:ss below an hour and h:mm:ss from an hour" {
  run fmt_time 0;    [ "$output" = 0:00 ]
  run fmt_time 75;   [ "$output" = 1:15 ]
  run fmt_time 3599; [ "$output" = 59:59 ]
  run fmt_time 3725; [ "$output" = 1:02:05 ]
}

@test "fmt_time truncates decimals and treats junk as zero" {
  run fmt_time 12.9; [ "$output" = 0:12 ]
  run fmt_time 08;   [ "$output" = 0:08 ]
  run fmt_time "";   [ "$output" = 0:00 ]
  run fmt_time -5;   [ "$output" = 0:00 ]
}

@test "emit_dedup drops only consecutive duplicates" {
  run emit_dedup <<< $'a\na\nb\na'
  [ "$status" -eq 0 ]
  [ "$output" = $'a\nb\na' ]
}

@test "poll_sleep blocks for the requested time on every call" {
  start=${EPOCHREALTIME/./}
  poll_sleep 0.1; poll_sleep 0.1; poll_sleep 0.1
  elapsed=$(( ${EPOCHREALTIME/./} - start ))
  [ "$elapsed" -ge 300000 ]
  [ "$elapsed" -lt 1000000 ]
}

@test "require returns 127 and names the missing tool" {
  rc=0; require bash ob-no-such-tool || rc=$?
  [ "$rc" -eq 127 ]
  [ "$MISSING_DEP" = ob-no-such-tool ]
}

@test "run_forever logs a missing dependency once per outage" {
  run timeout 1 bash -c 'source "$1"; s(){ MISSING_DEP=fake; return 127; }; OB_RETRY_MISSING=0.1 run_forever s' _ "$SCRIPTS/lib/core.sh"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"missing dependency fake"* ]]
}

@test "run_forever reconnects after the source exits" {
  run timeout 1 bash -c 'source "$1"; s(){ echo tick; }; OB_RETRY_RECONNECT=0.1 run_forever s' _ "$SCRIPTS/lib/core.sh"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -ge 5 ]
}

@test "ISLAND_STATE follows XDG_RUNTIME_DIR and falls back to /tmp" {
  run env XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" bash -c 'source "$1"; printf %s "$ISLAND_STATE"' _ "$SCRIPTS/lib/core.sh"
  [ "$output" = "$BATS_TEST_TMPDIR/run/eww-island" ]
  run env -u XDG_RUNTIME_DIR bash -c 'source "$1"; printf %s "$ISLAND_STATE"' _ "$SCRIPTS/lib/core.sh"
  [ "$output" = /tmp/eww-island ]
}

@test "island_eww passes --config with the eww dir and does not leak fd 9" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat > "$bin/eww" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
if [[ -e /proc/self/fd/9 ]]; then echo fd9-open; else echo fd9-closed; fi
EOF
  chmod +x "$bin/eww"
  exec 9> "$BATS_TEST_TMPDIR/lock"
  PATH="$bin:$PATH" run island_eww update a=1
  exec 9>&-
  [ "${lines[0]}" = "--config $REPO/eww update a=1" ]
  [ "${lines[1]}" = fd9-closed ]
}
