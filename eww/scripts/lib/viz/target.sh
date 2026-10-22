#!/usr/bin/env bash
# Capture target of viz: the playback stream owned by the active MPRIS player. Source it after core.sh.

# viz_descendant CHILD OWNER: CHILD is OWNER or one of its descendants.
viz_descendant() {
  local child=$1 owner=$2 key value parent
  local -A seen=()
  [[ $child =~ ^[1-9][0-9]*$ && $owner =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -r /proc/$owner/status ]] || return 1
  while [[ -r /proc/$child/status && ! ${seen[$child]+present} ]]; do
    [[ $child == "$owner" ]] && return 0
    seen[$child]=1
    parent=''
    while read -r key value _; do
      if [[ $key == PPid: ]]; then parent=$value; break; fi
    done < "/proc/$child/status"
    [[ $parent =~ ^[1-9][0-9]*$ ]] || return 1
    child=$parent
  done
  return 1
}

# Streams from in-process players (libmpv) may lack application.process.id;
# their client's pid then decides, preferring the socket-derived
# pipewire.sec.pid over the client-supplied application.process.id.
viz_client_pids() {
  pactl -f json list clients 2>/dev/null | jq -r '.[] | .properties as $p |
    [(.index | tostring),
     ([$p["pipewire.sec.pid"], $p["application.process.id"]] |
      map(select(. != null) | tostring | select(test("^[1-9][0-9]*$"))) | .[0] // "")] |
    join("|")' 2>/dev/null
}

# viz_select OWNER: sink-inputs JSON on stdin -> serial of OWNER's best stream (uncorked, then newest).
viz_select() {
  local owner=$1 rows pid serial rank client best='' best_rank=-1 pid_re='^[1-9][0-9]*$'
  local -A client_pid=()
  rows=$(jq -r '.[] | select(.corked == true or .corked == false) |
    [(.properties["application.process.id"] // ""),
     (.properties["object.serial"] // ""), (if .corked then 0 else 1 end), (.client // "")] |
    map(tostring) | join("|")') || return 0
  while IFS='|' read -r pid _ _ client; do
    [[ ! $pid =~ $pid_re && $client =~ ^[0-9]+$ ]] || continue
    while IFS='|' read -r client pid; do
      [[ $client =~ ^[0-9]+$ ]] && client_pid[$client]=$pid
    done < <(viz_client_pids)
    break
  done <<< "$rows"
  while IFS='|' read -r pid serial rank client; do
    if [[ ! $pid =~ $pid_re && $client =~ ^[0-9]+$ ]]; then pid=${client_pid[$client]-}; fi
    [[ $pid =~ $pid_re && $serial =~ ^[1-9][0-9]*$ && $rank =~ ^[01]$ ]] || continue
    viz_descendant "$pid" "$owner" || continue
    if (( rank > best_rank )) || { (( rank == best_rank )) && [[ $serial -gt ${best:-0} ]]; }; then
      best=$serial
      best_rank=$rank
    fi
  done <<< "$rows"
  [[ -z $best ]] || printf '%s\n' "$best"
  return 0
}

# viz_target INSTANCE: stream serial of MPRIS player INSTANCE, nothing when it has none.
viz_target() {
  local instance=$1 reply owner streams
  [[ -n $instance ]] || return 0
  reply=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus GetConnectionUnixProcessID s "org.mpris.MediaPlayer2.$instance" 2>/dev/null) || return 0
  [[ $reply =~ ^u\ ([1-9][0-9]*)$ ]] || return 0
  owner=${BASH_REMATCH[1]}
  streams=$(pactl -f json list sink-inputs 2>/dev/null) || return 0
  viz_select "$owner" <<< "$streams"
}
