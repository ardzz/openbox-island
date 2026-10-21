#!/usr/bin/env bash
## Launch the island (eww config ~/.config/eww-island). Restarts it when already running.
export LC_ALL=C.UTF-8
CFG="$HOME/.config/eww-island"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island.log"
E=(eww --config "$CFG")

fail() {
  dunstify -u critical -a eww-island "island gagal" "$1" >/dev/null 2>&1
  echo "island: $1" >&2
  exit 1
}

stop() {
  "${E[@]}" kill >/dev/null 2>&1
  for _ in {1..50}; do
    "${E[@]}" ping >/dev/null 2>&1 || break
    sleep 0.1
  done
  "${E[@]}" ping >/dev/null 2>&1 && {
    if [[ $1 == stop ]]; then
      echo "island: daemon lama tidak berhenti" >&2
      exit 1
    fi
    fail "daemon lama tidak berhenti"
  }
  rm -rf "${XDG_RUNTIME_DIR:-/tmp}/eww-island"
}

if [[ ${1:-} == stop ]]; then stop stop; exit 0; fi

command -v eww >/dev/null 2>&1 || fail "eww tidak ditemukan"
[[ -f $CFG/eww.yuck ]] || fail "config tidak ada di $CFG"

stop restart
mkdir -p "${LOG%/*}"
setsid -f "${E[@]}" daemon --no-daemonize >"$LOG" 2>&1 </dev/null || fail "daemon gagal start"
for _ in {1..50}; do
  "${E[@]}" ping >/dev/null 2>&1 && break
  sleep 0.1
done
"${E[@]}" ping >/dev/null 2>&1 || fail "daemon tidak merespons"
"${E[@]}" open island >/dev/null 2>&1 || fail "window island gagal dibuka"
