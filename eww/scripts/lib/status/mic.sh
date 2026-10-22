#!/usr/bin/env bash
# Microphone source of scripts/status. Source it; do not execute.

# mic_snapshot: the apps capturing a real input. Monitor sources, the visualizer and capture sinks
# do not count.
mic_snapshot() {
  local outputs sources report
  outputs=$(pactl -f json list source-outputs) || outputs=''
  sources=$(pactl -f json list short sources) || sources=''
  if ! report=$(jq -cn --argjson outputs "$outputs" --argjson sources "$sources" '
    if ($outputs | type) != "array" or ($sources | type) != "array" then
      error("Expected pactl arrays")
    else
    [$outputs[] | . as $output |
      ($sources | map(select((.index | tostring) == ($output.source | tostring))) | .[0].name // "") as $source |
      select(($source | endswith(".monitor") | not) and
        (.properties["application.name"] != "eww-island-viz") and
        (.properties["stream.capture.sink"] != "true")) |
      [.properties["application.name"], .properties["application.process.binary"], "Aplikasi"] |
      map(select(. != null and . != "")) | .[0]] | unique |
    {source:"mic",active:(length > 0),apps:join(", ")}
    end' 2>/dev/null); then
    report='{"source":"mic","active":false,"apps":""}'
  fi
  printf '%s\n' "$report"
}

# mic_event LINE: a pactl subscribe line; server, source-output and source events refresh.
mic_event() {
  case $1 in
    *' on server'*|*' on source-output #'*|*' on source #'*) mic_snapshot ;;
  esac
}

mic_idle() { printf '{"source":"mic","active":false,"apps":""}\n'; }
