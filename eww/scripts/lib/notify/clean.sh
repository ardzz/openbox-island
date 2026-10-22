#!/usr/bin/env bash
# Notification text as the island shows it. Source it after core.sh; do not execute.

# shellcheck disable=SC2034 # ICON_BELL and CLEAN_JQ are read by the sourcing scripts
# Shown when a notification has no usable image.
ICON_BELL=$'\U000F009A'

# jq definitions. clean: eww labels show plain text, so markup tags are dropped, entities decoded and
# whitespace collapsed. file_uri: a path as a percent-encoded file:// URI. island_shows: an
# {id, app, tag} object the island lists (not its own failures, not the volume/backlight OSD).
CLEAN_JQ='def clean: tostring | gsub("[[:cntrl:]]"; " ") | gsub("<[^>]*>"; "")
    | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&quot;"; "\"") | gsub("&(apos|#39);"; "'"'"'")
    | gsub("&amp;"; "&") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");
  def file_uri: "file://" + (split("/") | map(@uri) | join("/"));
  def island_shows: .id > 0 and .app != "eww-island" and (.tag | IN("obvolume", "obbacklight") | not);'

# field VAR VALUE MAX: VALUE with control characters as spaces, cut to MAX characters.
field() {
  local value=${2//[[:cntrl:]]/ }
  printf -v "$1" '%s' "${value:0:$3}"
}
