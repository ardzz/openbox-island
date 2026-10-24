#!/usr/bin/env bash
# Meeting prep templates: one "POLA | SEBELUM | item; item; ..." line per meeting series.
# Source it after core.sh and lib/todo/deadline.sh; do not execute.
PREP_FILE="${ISLAND_PREP:-${XDG_CONFIG_HOME:-$HOME/.config}/openbox-island/prep}"

# prep_file: the current template path, following ISLAND_PREP when it changes after sourcing.
prep_file() { printf '%s' "${ISLAND_PREP:-$PREP_FILE}"; }

# prep_trim VAR: strip leading and trailing whitespace from VAR in place.
prep_trim() {
  local -n v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
}

# prep_items TEXT: print TEXT split on ";", trimmed, empties dropped, as a compact JSON array.
prep_items() {
  jq -cn --arg text "$1" \
    '$text | split(";") | map(gsub("^\\s+|\\s+\\z"; "")) | map(select(length > 0))'
}

# prep_before_ok SPEC: SPEC is empty, Nm, Nj or Nh.
prep_before_ok() { [[ -z $1 || $1 =~ ^[0-9]+[mjh]$ ]]; }

# prep_parse LINE: set prep_p_pattern/before/items for a valid template line.
# Returns 1 for blank, comment or bad lines. The raw fields keep their spelling.
prep_parse() {
  local line=$1 rest
  prep_p_pattern='' prep_p_before='' prep_p_items='[]'
  [[ $line =~ ^[[:space:]]*(#|$) ]] && return 1
  [[ $line == *'|'*'|'* ]] || return 1
  prep_p_pattern=${line%%|*}; rest=${line#*|}
  prep_p_before=${rest%%|*}; rest=${rest#*|}
  prep_trim prep_p_pattern; prep_trim prep_p_before
  prep_p_items=$(prep_items "$rest")
  [[ -n $prep_p_pattern ]] && prep_before_ok "$prep_p_before" && [[ $prep_p_items != '[]' ]]
}

# prep_lines: print one tab-separated record per valid template line:
# pattern TAB before TAB items-json TAB line-no. Bad lines are reported on stderr.
prep_lines() {
  local line n=0 file
  file=$(prep_file)
  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    n=$(( n + 1 ))
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    if ! prep_parse "$line"; then
      printf 'prep: baris %d dilewati\n' "$n" >&2
      continue
    fi
    printf '%s\t%s\t%s\t%d\n' "${prep_p_pattern,,}" "$prep_p_before" "$prep_p_items" "$n"
  done < "$file"
}

# prep_templates: the templates as one compact JSON array [{pattern, before, items, line}].
prep_templates() {
  prep_lines | jq -Rcn '[inputs | split("\t")
    | {pattern: .[0], before: .[1], items: (.[2] | fromjson), line: (.[3] | tonumber)}]'
}

# prep_match TITLE: the first template whose pattern is a substring of TITLE, or status 1.
prep_match() {
  local title=${1,,} pattern before items n
  while IFS=$'\t' read -r pattern before items n; do
    if [[ $title == *"$pattern"* ]]; then
      jq -cn --arg p "$pattern" --arg b "$before" --argjson items "$items" --argjson line "$n" \
        '{pattern: $p, before: $b, items: $items, line: $line}'
      return 0
    fi
  done < <(prep_lines 2>/dev/null)
  return 1
}

# prep_due START SPEC: the epoch prep items are due: START minus SPEC (Nm minutes,
# Nj hours, Nh days at ISLAND_DEADLINE_TIME); empty SPEC uses ISLAND_PREP_BEFORE.
prep_due() {
  local start=$1 spec=${2:-${ISLAND_PREP_BEFORE:-2j}} n='' unit=''
  if [[ $spec =~ ^([0-9]+)([mjh])$ ]]; then n=${BASH_REMATCH[1]} unit=${BASH_REMATCH[2]}
  else n=2 unit=j; fi
  case $unit in
    m) printf '%s\n' "$(( start - 10#$n * 60 ))" ;;
    j) printf '%s\n' "$(( start - 10#$n * 3600 ))" ;;
    h) deadline_at "$start" "-$((10#$n))" "${ISLAND_DEADLINE_TIME:-17:00}" ;;
  esac
}

# prep_save TITLE ANSWER: set the items of the first template matching TITLE to ANSWER
# (split on ";"); an empty answer deletes that line, no match appends one. Atomic write.
prep_save() {
  local title=$1 items line tmp found=0 out=() joined file
  local title_lower=${title,,}
  file=$(prep_file)
  items=$(prep_items "$2")
  joined=$(jq -r 'join("; ")' <<< "$items")
  if [[ -r $file ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      if (( ! found )) && prep_parse "${line%$'\r'}" \
        && [[ $title_lower == *"${prep_p_pattern,,}"* ]]; then
        found=1
        if [[ $items != '[]' ]]; then
          if [[ -n $prep_p_before ]]; then
            out+=("$prep_p_pattern | $prep_p_before | $joined")
          else
            out+=("$prep_p_pattern |  | $joined")
          fi
        fi
        continue
      fi
      out+=("$line")
    done < "$file"
  fi
  if (( ! found )); then
    [[ $items == '[]' ]] && return 0
    out+=("${title//|/ } |  | $joined")
  fi
  mkdir -p -- "${file%/*}" || return 1
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  if (( ${#out[@]} )); then
    printf '%s\n' "${out[@]}" > "$tmp" || { rm -f -- "$tmp"; return 1; }
  else
    : > "$tmp" || { rm -f -- "$tmp"; return 1; }
  fi
  mv -f -- "$tmp" "$file"
}
