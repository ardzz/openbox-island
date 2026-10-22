#!/usr/bin/env bash
# FIFO-driven deflisten loop. Source it after core.sh; do not execute.

# listen_tick: seconds without input after which HANDLE_FN gets "@tick"; 0 = never.
# Read on every loop iteration, so a handler may change it.
listen_tick=${listen_tick:-0}

# listen NAME RENDER_FN HANDLE_FN: own the FIFO $ISLAND_STATE/NAME.fifo and print RENDER_FN's output
# at start and whenever it changes. Each FIFO line goes to HANDLE_FN; lines within LISTEN_SETTLE
# seconds (0.15) of the first are rendered once. Never returns; the FIFO goes away when it exits.
listen() {
  local render_fn=$2 handle_fn=$3 line last='' settle_us deadline=0 active wake
  local tick_seen='' tick_us=0 remaining timeout
  listen_fifo="$ISLAND_STATE/$1.fifo"
  settle_us=$(seconds_us "${LISTEN_SETTLE:-0.15}")
  mkdir -p "$ISLAND_STATE" || return
  rm -f -- "$listen_fifo"
  mkfifo -m 600 "$listen_fifo" || return
  exec {listen_fd}<> "$listen_fifo"
  trap 'exit 0' TERM INT HUP
  trap listen_cleanup EXIT
  listen_render
  active=${EPOCHREALTIME/./}
  while true; do
    if [[ ${listen_tick:-0} != "$tick_seen" ]]; then
      tick_seen=${listen_tick:-0} tick_us=0
      if [[ $tick_seen =~ ^[0-9]+(\.[0-9]+)?$ ]]; then tick_us=$(seconds_us "$tick_seen"); fi
    fi
    wake=$deadline
    if (( ! wake && tick_us )); then wake=$((active + tick_us)); fi
    if (( wake )); then
      remaining=$((wake - ${EPOCHREALTIME/./}))
      if (( remaining <= 0 )); then
        if (( deadline )); then
          deadline=0
        else
          active=${EPOCHREALTIME/./}
          "$handle_fn" '@tick'
        fi
        listen_render
        continue
      fi
      printf -v timeout '%d.%06d' "$((remaining / 1000000))" "$((remaining % 1000000))"
      IFS= read -r -t "$timeout" -u "$listen_fd" line || continue
    else
      IFS= read -r -u "$listen_fd" line || continue
    fi
    active=${EPOCHREALTIME/./}
    "$handle_fn" "$line"
    (( deadline )) || deadline=$((active + settle_us))
  done
}

# listen_render: print listen's RENDER_FN output unless it failed or equals the last one printed.
listen_render() {
  local out
  out=$("$render_fn") || return 0
  [[ $out != "$last" ]] || return 0
  printf '%s\n' "$out"
  last=$out
}

listen_cleanup() {
  # A newer listener may already own the path.
  if [[ $listen_fifo -ef /proc/$BASHPID/fd/$listen_fd ]]; then rm -f -- "$listen_fifo"; fi
}
