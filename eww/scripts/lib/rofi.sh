#!/usr/bin/env bash
# island_rofi PLACEHOLDER ARGS...: rofi -dmenu ARGS in the island's look (eww/rofi/island.rasi),
# its text colours and font taken from the bar palette when eww/_colors.scss exists. Source it.

island_rofi() {
  local placeholder=$1 root fg='' font='' line theme
  shift
  root=$(dirname "$DIR")
  while IFS= read -r line; do
    if [[ $line =~ ^\$fg:\ *(#[0-9a-fA-F]{6})\; ]]; then fg=${BASH_REMATCH[1]}
    elif [[ $line =~ ^\$font:\ *\"([^\"]+)\"\; ]]; then font=${BASH_REMATCH[1]}; fi
  done 2> /dev/null < "$root/_colors.scss"
  # One rule per line: rofi's -theme-str lexer joins two quoted strings on the same line.
  theme="entry { placeholder: \"$placeholder\"; }"
  # The panel is black, so alpha over it equals the island's mix() of fg into black.
  [[ -z $fg ]] || theme+=$'\n'"* { fg: $fg; muted: ${fg}99; track: ${fg}2e; }"
  if [[ -n $font ]]; then
    theme+=$'\n'"* { font: \"$font 10\"; }"$'\n'"prompt { font: \"$font Bold 8\"; }"
    theme+=$'\n'"textbox { font: \"$font 8\"; }"
  fi
  rofi -dmenu -theme "$root/rofi/island.rasi" -theme-str "$theme" "$@"
}
