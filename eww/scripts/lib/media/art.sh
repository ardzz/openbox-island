#!/usr/bin/env bash
# Cover art for MPRIS artUrls: local paths, safe aliases and downloaded covers. Source it after core.sh.

ART_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/art"

# resolve_art URL: local image path for an MPRIS artUrl ("" when unavailable), always safe inside a single-quoted CSS url().
resolve_art() {
  local url=$1 path file
  case $url in
    file://*)
      path=${url#file://}
      printf -v path '%b' "${path//\%/\\x}"
      if [[ ! -f $path || ! -r $path ]]; then printf '\n'; return 0; fi
      if [[ $path == *"'"* || $path == *\\* || $path == *$'\n'* ]]; then
        file="$ART_CACHE/$(printf '%s' "$path" | sha1sum | cut -c1-40)"
        mkdir -p "$ART_CACHE"
        ln -sfn "$path" "$file"
        printf '%s\n' "$file"
      else
        printf '%s\n' "$path"
      fi ;;
    http://*|https://*)
      file="$ART_CACHE/$(printf '%s' "$url" | sha1sum | cut -c1-40)"
      if [[ ! -s $file ]]; then
        mkdir -p "$ART_CACHE"
        if ! curl -sfL --max-time 3 -o "$file.part" "$url"; then
          rm -f "$file.part"
          printf '\n'
          return 0
        fi
        mv "$file.part" "$file"
      fi
      printf '%s\n' "$file" ;;
    *) printf '\n' ;;
  esac
}
