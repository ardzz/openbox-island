# tests/lib/monitor.bats
setup() {
  load ../helpers
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/monitor.sh"
  got=()
}

record() { got+=("$1"); }

@test "monitor_run hands every line to the handler in order" {
  monitor_run record printf '%s\n' a 'b c' d
  [ "${#got[@]}" = 3 ]
  [ "${got[0]}" = a ] && [ "${got[1]}" = 'b c' ] && [ "${got[2]}" = d ]
  [ -z "$monitor_pid" ]
}

@test "monitor_run returns once the command exits" {
  local start elapsed
  start=${EPOCHREALTIME/./}
  monitor_run record sh -c 'echo x; sleep 0.2; echo y'
  elapsed=$(( ${EPOCHREALTIME/./} - start ))
  [ "${got[*]}" = 'x y' ]
  [ "$elapsed" -ge 200000 ] && [ "$elapsed" -lt 2000000 ]
}

@test "monitor_start runs before the first line" {
  started() { got+=(start); }
  monitor_start=started
  monitor_run record echo a
  [ "${got[*]}" = 'start a' ]
}

@test "workers_stop leaves no worker behind" {
  sleeper() { exec sleep 30; }
  looper() { while :; do sleep 0.05; done; }
  workers_start sleeper looper 3>&-
  [ "${#worker_pids[@]}" = 2 ]
  kill -0 "${worker_pids[0]}" && kill -0 "${worker_pids[1]}"
  workers_stop
  [ "${#worker_pids[@]}" = 0 ]
  local me=$BASHPID
  pgrep -P "$me" > "$BATS_TEST_TMPDIR/children" || :
  [ ! -s "$BATS_TEST_TMPDIR/children" ]
}

@test "workers inherit the caller's stdout" {
  hello() { echo "hi $BASHPID"; }
  workers_start hello hello > "$BATS_TEST_TMPDIR/out" 3>&-
  wait "${worker_pids[@]}"
  [ "$(grep -c '^hi ' "$BATS_TEST_TMPDIR/out")" = 2 ]
}
