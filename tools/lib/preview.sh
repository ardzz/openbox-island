#!/usr/bin/env bash
# Private, frozen eww config copies for tools/preview and tools/showcase. Source it; do not execute.
# preview_prepare copies a config to COPY with every listener and poll frozen to a plain variable,
# the windows 300px down and a backdrop window; preview_start runs a daemon on it under a
# private runtime dir RUN; preview_cleanup removes all of it again.
# PREVIEW_BACKDROP: the backdrop's CSS colour or gradient, default #808080.

COPY='' RUN=''
PREVIEW_BACKDROP_WINDOW='(defwindow preview-backdrop
  :monitor 0
  :geometry (geometry :x "0px" :y "300px" :width "520px" :height "230px" :anchor "top center")
  :wm-ignore true
  (box :class "preview-backdrop"))'
# A pointer resting over the region must not leave tooltips in the picture.
PREVIEW_TOOLTIP_CSS='tooltip { opacity: 0; }'
# :not(#id) gives id specificity, beating class rules such as the skeleton pulse (GTK has no !important).
PREVIEW_STILL_CSS='*:not(#preview-none) { animation: none; transition: none; }'

ew() { XDG_RUNTIME_DIR=$RUN eww --config "$COPY" "$@"; }

# preview_cleanup: stop the daemon, then drop the copy, the runtime dir and the log eww keeps per socket.
preview_cleanup() {
  local socket
  local -a sockets=()
  if [[ -n $RUN ]]; then sockets=("$RUN"/eww-server_*); fi
  if [[ -n $COPY ]]; then
    ew kill >/dev/null 2>&1 || :
    pkill -f "eww --config $COPY( |\$)" 2>/dev/null || :
    rm -rf "$COPY"
  fi
  for socket in "${sockets[@]}"; do
    [[ $socket == *'*' ]] || rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/eww/eww_${socket##*/eww-server_}.log"
  done
  if [[ -n $RUN ]]; then rm -rf "$RUN"; fi
  COPY='' RUN=''
}

# preview_sample FILE: SAMPLE_WINDOW, SAMPLE_TAB and the "var=json" lines in SAMPLE_UPDATES, with
# @ASSETS@ standing for the absolute path of the assets/ folder next to FILE. Status 2 on a bad line.
# shellcheck disable=SC2034 # read by the tools that source this file
preview_sample() {
  local line assets
  assets="$(cd "$(dirname "$1")" && pwd)/assets"
  SAMPLE_WINDOW='' SAMPLE_TAB='' SAMPLE_UPDATES=()
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      ''|'#'*) ;;
      window=*) SAMPLE_WINDOW=${line#window=} ;;
      tab=*) SAMPLE_TAB=${line#tab=} ;;
      ?*=*) SAMPLE_UPDATES+=("${line//@ASSETS@/$assets}") ;;
      *) printf 'preview: baris sampel tidak dikenal: %s\n' "$line" >&2; return 2 ;;
    esac
  done < "$1"
}

# preview_freeze FILE: windows 300px down; every deflisten/defpoll becomes a defvar holding its :initial.
preview_freeze() {
  sed -E -i \
    -e 's/(:y[[:space:]]+)"0px"/\1"300px"/g' \
    -e "s/^([[:space:]]*)\\((deflisten|defpoll)[[:space:]]+([^[:space:]]+)[[:space:]].*:initial[[:space:]]+('[^']*'|\"[^\"]*\").*\\)[[:space:]]*\$/\\1(defvar \\3 \\4)/" \
    -e 's/^([[:space:]]*)\((deflisten|defpoll)[[:space:]]+([^[:space:]]+)([[:space:]].*)?$/\1(defvar \3 "")/' \
    "$1"
}

# preview_prepare CONFIG_DIR [still]: the frozen copy in COPY; "still" also turns animations off.
# The caller traps preview_cleanup first.
preview_prepare() {
  local config=$1 mode=${2:-} file css backdrop=${PREVIEW_BACKDROP:-#808080} property=background-color
  # GTK takes gradients only as background-image.
  if [[ $backdrop == *gradient* ]]; then property=background-image; fi
  css=".preview-backdrop { $property: $backdrop; }"$'\n'$PREVIEW_TOOLTIP_CSS
  COPY=$(mktemp -d /tmp/island-preview.XXXX)
  RUN="$COPY.run"
  mkdir -m 700 "$RUN"
  cp -a "$config/." "$COPY/"
  while IFS= read -r -d '' file; do preview_freeze "$file"; done < <(find "$COPY" -name '*.yuck' -print0)
  if grep -rqE --include='*.yuck' '\((deflisten|defpoll)([[:space:]]|$)' "$COPY"; then
    printf 'preview: deflisten/defpoll yang tidak satu baris tidak bisa dibekukan\n' >&2
    return 1
  fi
  # The caller opens and closes the card: a pointer resting over the windows must not.
  if [[ -f $COPY/scripts/island ]]; then printf '#!/bin/sh\n' > "$COPY/scripts/island"; fi
  # The backdrop hides whatever the screen shows behind transparent parts of the island.
  printf '\n%s\n' "$PREVIEW_BACKDROP_WINDOW" >> "$COPY/eww.yuck"
  if [[ $mode == still ]]; then css+=$'\n'$PREVIEW_STILL_CSS; fi
  for file in "$COPY/eww.scss" "$COPY/eww.css"; do
    if [[ -f $file ]]; then printf '\n%s\n' "$css" >> "$file"; fi
  done
}

# preview_start: the daemon on COPY, with the backdrop open.
preview_start() {
  ew daemon >/dev/null 2>&1
  for _ in {1..50}; do ew ping >/dev/null 2>&1 && break; sleep 0.1; done
  ew open preview-backdrop >/dev/null
}
