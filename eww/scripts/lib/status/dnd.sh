#!/usr/bin/env bash
# Do-not-disturb (dunst paused) source of scripts/status. Source it; do not execute.

# dbus-monitor rules: dunst's paused property and dunst (re)starting.
# shellcheck disable=SC2034 # read by scripts/status
DND_MATCH=(
  "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/Notifications'"
  "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.Notifications'"
)

# dnd_snapshot: active only when dunstctl says literally true.
dnd_snapshot() {
  local paused
  paused=$(dunstctl is-paused 2>/dev/null) || paused=false
  if [[ $paused == true ]]; then
    printf '{"source":"dnd","active":true,"apps":""}\n'
  else
    printf '{"source":"dnd","active":false,"apps":""}\n'
  fi
}

# dnd_event LINE: a dbus-monitor line; the signal headers refresh.
dnd_event() {
  case $1 in
    *member=PropertiesChanged*|*member=NameOwnerChanged*) dnd_snapshot ;;
  esac
}

dnd_idle() { printf '{"source":"dnd","active":false,"apps":""}\n'; }
