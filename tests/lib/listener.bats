# tests/lib/listener.bats
setup() {
  load ../helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/listener.sh"
  OUT="$BATS_TEST_TMPDIR/out" LOG="$BATS_TEST_TMPDIR/log" FIFO="$ISLAND_STATE/t.fifo"
  value=0 ticks=0
}

teardown() {
  if [[ -n ${pid:-} ]]; then kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; fi
}

render() { echo render >> "$LOG"; printf 'v%s\n' "$value"; }
handle() {
  echo "handle $1" >> "$LOG"
  case $1 in
    'set '*) value=${1#set } ;;
    on) listen_tick=0.1 ;;
    off) listen_tick=0 ;;
    @tick) ticks=$((ticks + 1)); value=tick$ticks ;;
  esac
}

# start: run the listener in the background until its FIFO exists.
start() {
  listen t render handle > "$OUT" 3>&- &
  pid=$!
  local i
  for i in $(seq 100); do [[ -p $FIFO ]] && return 0; sleep 0.02; done
  return 1
}

count() { grep -c "^$1\$" "$LOG" || :; }

@test "renders once at start" {
  start
  sleep 0.3
  [ "$(cat "$OUT")" = v0 ]
  [ "$(count render)" = 1 ]
}

@test "an unchanged render is not printed again, a changed one is" {
  start
  fifo_signal t 'set 0'
  sleep 0.4
  fifo_signal t 'set 1'
  sleep 0.4
  [ "$(cat "$OUT")" = $'v0\nv1' ]
  [ "$(count render)" = 3 ]
}

@test "lines within the settle time are all handled and rendered once" {
  start
  local v
  for v in a b c d e; do fifo_signal t "set $v"; done
  sleep 0.5
  [ "$(grep -c '^handle set' "$LOG")" = 5 ]
  [ "$(count render)" = 2 ]
  [ "$(cat "$OUT")" = $'v0\nve' ]
}

@test "@tick fires only while listen_tick is above zero" {
  start
  sleep 0.4
  [ "$(count 'handle @tick')" = 0 ]
  fifo_signal t on
  sleep 0.7
  [ "$(count 'handle @tick')" -ge 3 ]
  fifo_signal t off
  sleep 0.3
  local stopped
  stopped=$(count 'handle @tick')
  sleep 0.4
  [ "$(count 'handle @tick')" = "$stopped" ]
  [ "$(tail -n 1 "$OUT")" = "vtick$stopped" ]
}

@test "the FIFO is removed on TERM" {
  start
  kill -TERM "$pid"
  wait "$pid" || :
  pid=''
  [ ! -e "$FIFO" ]
}
