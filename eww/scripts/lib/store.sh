#!/usr/bin/env bash
# Locked, atomically replaced JSON files. Source it after core.sh; do not execute.

# store_valid FILE: print FILE's JSON compacted when it holds exactly one JSON value.
store_valid() {
  jq -cs 'if length == 1 then .[0] else error("not one value") end' "$1" 2>/dev/null
}

# store_read FILE DEFAULT_JSON: FILE's JSON, or DEFAULT_JSON when it is missing or invalid.
# Readers take no lock: writers replace the file with a rename.
store_read() {
  store_valid "$1" || printf '%s\n' "$2"
}

# store_update FILE DEFAULT_JSON JQ_FILTER [JQ ARGS...]: apply JQ_FILTER to FILE (DEFAULT_JSON when
# missing) under a lock on FILE.lock and replace FILE atomically. A corrupt FILE is kept as FILE.corrupt.
# Fails with jq's status, saving nothing, when the filter errors or answers null, false or not one value.
store_update() {
  local file=$1 default=$2 filter=$3 fd doc='' new tmp rc=0
  shift 3
  mkdir -p -- "${file%/*}" || return
  exec {fd}> "$file.lock" || return
  if ! flock "$fd"; then exec {fd}>&-; return 1; fi
  if [[ -e $file ]] && ! doc=$(store_valid "$file"); then
    mv -f -- "$file" "$file.corrupt"
    doc=''
  fi
  new=$(jq -ce "$@" "$filter" <<< "${doc:-$default}") || rc=$?
  if (( rc == 0 )) && [[ $new == *$'\n'* ]]; then rc=5; fi
  if (( rc == 0 )); then tmp=$(mktemp "$file.XXXXXX") || rc=1; fi
  if (( rc == 0 )) && ! { printf '%s\n' "$new" > "$tmp" && mv -f -- "$tmp" "$file"; }; then
    rm -f -- "$tmp"
    rc=1
  fi
  exec {fd}>&-
  return "$rc"
}
