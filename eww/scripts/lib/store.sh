#!/usr/bin/env bash
# Locked, atomically replaced JSON files. Source it after core.sh; do not execute.

# STORE_VALID_JQ: optional jq expression a stored value must answer exactly true for; a value
# failing it counts as corrupt. Unset = any single JSON value.

# store_valid FILE: print FILE's JSON compacted when it holds exactly one valid JSON value.
store_valid() {
  jq -cs "if length == 1 and ([.[0] | ${STORE_VALID_JQ:-true}] == [true]) then .[0] else error(\"invalid\") end" \
    "$1" 2>/dev/null
}

# store_read FILE DEFAULT_JSON: FILE's JSON, or DEFAULT_JSON when it is missing, invalid or corrupt.
# Readers take no lock: writers replace the file with a rename.
store_read() {
  store_valid "$1" || printf '%s\n' "$2"
}

# store_update FILE DEFAULT_JSON JQ_FILTER [JQ ARGS...]: apply JQ_FILTER to FILE (DEFAULT_JSON when
# missing) under a lock on FILE.lock and replace FILE atomically. A corrupt FILE (unparsable or failing
# STORE_VALID_JQ) is kept as FILE.corrupt and replaced by the result for DEFAULT_JSON.
# Fails with jq's status, saving nothing, when the filter errors or answers null, false or not one value.
# With STORE_EMIT_DOC=1 the saved JSON is also printed to stdout.
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
  if (( rc == 0 )) && [[ ${STORE_EMIT_DOC:-} == 1 ]]; then printf '%s' "$new"; fi
  return "$rc"
}
