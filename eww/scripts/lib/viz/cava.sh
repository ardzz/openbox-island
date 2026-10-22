#!/usr/bin/env bash
# CAVA side of viz: frame parsing, frame rate and the runtime config. Source it after core.sh.

# viz_frame LINE: six raw CAVA levels 0-12 ("a;b;c;d;e;f;") into VIZ_FRAME as a JSON array.
viz_frame() {
  [[ $1 =~ ^((1[0-2]|[0-9])\;){6}$ ]] || return 1
  VIZ_FRAME=${1%;}
  VIZ_FRAME="[${VIZ_FRAME//;/,}]"
}

viz_frames() {
  local line VIZ_FRAME
  while IFS= read -r line; do
    if viz_frame "$line"; then printf '%s\n' "$VIZ_FRAME"; fi
  done
  return 0
}

# Integer fps: valid ISLAND_VIZ_FPS, else the current refresh rate of the output at the
# screen origin (or the primary), clamped to 1..240; 60 when that cannot be read.
viz_fps() {
  local fps=${ISLAND_VIZ_FPS-} line xrandr hz on_origin=0 on_primary=0 origin='' primary=''
  if [[ $fps =~ ^[1-9][0-9]{0,2}$ ]] && (( fps <= 240 )); then
    printf '%s\n' "$fps"
    return 0
  fi
  fps=60
  if [[ -n ${DISPLAY-} ]] && command -v xrandr >/dev/null 2>&1; then
    xrandr=$(xrandr --current 2>/dev/null) || xrandr=''
    while IFS= read -r line; do
      if [[ $line != [[:space:]]* ]]; then
        on_origin=0 on_primary=0
        [[ $line =~ ^[^[:space:]]+\ connected(\ primary)?\ [0-9]+x[0-9]+\+([0-9]+)\+([0-9]+) ]] || continue
        [[ -z ${BASH_REMATCH[1]} ]] || on_primary=1
        (( 10#${BASH_REMATCH[2]} || 10#${BASH_REMATCH[3]} )) || on_origin=1
      elif (( on_origin || on_primary )) && [[ $line =~ [[:space:]]([0-9]+)(\.([0-9]*))?\* ]]; then
        hz=$(( 10#${BASH_REMATCH[1]} ))
        [[ ${BASH_REMATCH[3]:0:1} != [5-9] ]] || hz=$((hz + 1))
        if (( on_origin )) && [[ -z $origin ]]; then origin=$hz; fi
        if (( on_primary )) && [[ -z $primary ]]; then primary=$hz; fi
      fi
    done <<< "$xrandr"
    hz=${origin:-$primary}
    if [[ -n $hz ]]; then
      fps=$(( hz < 1 ? 1 : hz > 240 ? 240 : hz ))
    fi
  fi
  printf '%s\n' "$fps"
}

# CAVA's integral filter keeps mem*nr/(66/fps)^0.1 of the previous frame, a settle time
# tau = 1/(fps*(1 - nr/(66/fps)^0.1)). Solve for nr so tau stays that of 90 at 60 fps:
# nr = 100*(1 - 1/(tau*fps))*(66/fps)^0.1, clamped to 0..100.
viz_cava_config() {
  awk -v fps="$1" '
    BEGIN {
      tau = 1 / (60 * (1 - 0.90 * (60 / 66) ^ 0.1))
      nr = 100 * (1 - 1 / (tau * fps)) * (66 / fps) ^ 0.1
      nr = nr < 0 ? 0 : nr > 100 ? 100 : nr
    }
    /^framerate = / { print "framerate = " fps; next }
    /^noise_reduction = / { printf "noise_reduction = %.0f\n", nr; next }
    { print }' "$ISLAND_CFG/cava.conf"
}
