# tests/lib.bats
setup() { load helpers; source "$SCRIPTS/lib.sh"; }

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

@test "require returns 127 and names the missing tool" {
  rc=0; require bash ob-no-such-tool || rc=$?
  [ "$rc" -eq 127 ]
  [ "$MISSING_DEP" = ob-no-such-tool ]
}

@test "run_forever logs a missing dependency once per outage" {
  run timeout 1 bash -c 'source "$1"; s(){ MISSING_DEP=fake; return 127; }; OB_RETRY_MISSING=0.1 run_forever s' _ "$SCRIPTS/lib.sh"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"missing dependency fake"* ]]
}

@test "run_forever reconnects after the source exits" {
  run timeout 1 bash -c 'source "$1"; s(){ echo tick; }; OB_RETRY_RECONNECT=0.1 run_forever s' _ "$SCRIPTS/lib.sh"
  [ "$status" -eq 124 ]
  [ "${#lines[@]}" -ge 5 ]
}
