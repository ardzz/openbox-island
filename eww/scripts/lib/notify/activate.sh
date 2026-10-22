#!/usr/bin/env bash
# Bring a notification's app to the front. Source it after core.sh; do not execute.

# regex_quote VAR TEXT: TEXT with POSIX ERE metacharacters escaped.
regex_quote() {
  local text=$2 quoted='' char i
  for ((i = 0; i < ${#text}; i++)); do
    char=${text:i:1}
    case $char in
      [].[\\*+?^\$\{\}\(\)\|]) quoted+="\\$char" ;;
      *) quoted+=$char ;;
    esac
  done
  printf -v "$1" '%s' "$quoted"
}

# activate APP ENTRY: raise the app's window, else launch its desktop entry.
# dunst cannot run the real default action: hidden notifications are already closed on D-Bus.
activate() {
  local app=$1 entry=$2 class='' dir line name flag pattern window
  local -a dirs
  [[ $entry =~ ^[A-Za-z0-9._-]+$ ]] || entry=''
  if [[ -n $entry ]]; then
    IFS=: read -ra dirs <<< "${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${dirs[@]}"; do
      [[ -f $dir/applications/$entry.desktop ]] || continue
      while IFS= read -r line; do
        if [[ $line == StartupWMClass=* ]]; then class=${line#*=}; break; fi
      done < "$dir/applications/$entry.desktop"
      break
    done
  fi
  for name in "$class" "$entry" "$app"; do
    [[ -n $name ]] || continue
    regex_quote pattern "$name"
    for flag in --class --classname; do
      window=$(xdotool search --onlyvisible --limit 1 "$flag" "^$pattern\$") || continue
      window=${window%%$'\n'*}
      if [[ -n $window ]]; then xdotool windowactivate "$window"; return; fi
    done
  done
  if [[ -n $entry ]]; then setsid -f gtk-launch "$entry"; fi
}
