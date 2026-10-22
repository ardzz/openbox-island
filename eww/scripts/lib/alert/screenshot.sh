#!/usr/bin/env bash
# Alert source: new screenshots with a thumbnail (inotifywait). Source it; do not execute.

ICON_CAMERA=$'\U000F0100'

screenshot_init() {
  alert_need inotifywait || return
  screenshot_path=$(screenshot_dir)
  mkdir -p "$screenshot_path" || alert_skip "$screenshot_path tidak dapat dibuat"
}

screenshot_monitor() {
  printf '%s\0' inotifywait -m -q -e close_write,moved_to --format '%w%f' "$screenshot_path"
}

screenshot_dir() {
  local pictures=''
  if [[ -n ${ISLAND_SCREENSHOT_DIR:-} ]]; then
    printf '%s\n' "$ISLAND_SCREENSHOT_DIR"
    return
  fi
  if command -v xdg-user-dir > /dev/null 2>&1; then
    pictures=$(xdg-user-dir PICTURES 2>/dev/null) || pictures=''
  fi
  # Same directory ob-screenshot saves to; xdg-user-dir answers $HOME when PICTURES is unset.
  [[ -n $pictures ]] || pictures=$HOME
  printf '%s\n' "${pictures%/}/Screenshots"
}

screenshot_snapshot() { :; }

screenshot_event() {
  case ${1,,} in
    *.png|*.jpg|*.jpeg) alert_json screenshot "$ICON_CAMERA" 'Tangkapan layar' "${1##*/}" -1 "$1" ;;
  esac
}
