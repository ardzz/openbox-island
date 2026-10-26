#!/usr/bin/env bash
# Cover tints cached by image contents, independent of rotating player paths.

art_color() {
  local path=${1:-} cache key histogram color
  if [[ ! -f $path || ! -r $path ]]; then printf '\n'; return 0; fi
  if ! key=$(sha1sum < "$path" 2>/dev/null); then printf '\n'; return 0; fi
  key=${key%% *}
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/art-color"
  if [[ -f $cache/$key && -r $cache/$key ]]; then
    IFS= read -r color < "$cache/$key" || color=''
    printf '%s\n' "$color"
    return 0
  fi
  if ! histogram=$(LC_ALL=C magick "$path" -resize 12x12! -alpha remove -format %c histogram:info:- 2>/dev/null); then
    printf '\n'; return 0
  fi
  color=$(LC_ALL=C awk '
    function channel(c) { return c ~ /%/ ? c * 2.55 : c + 0 }
    /s?rgba?\(/ {
      count = $1 + 0
      pixel = $0
      sub(/^.*s?rgba?\(/, "", pixel)
      sub(/\).*$/, "", pixel)
      split(pixel, rgb, ",")
      r = channel(rgb[1]); g = channel(rgb[2]); b = channel(rgb[3])
      max = r > g ? r : g; max = max > b ? max : b
      min = r < g ? r : g; min = min < b ? min : b
      sat = max ? (max - min) / max : 0
      base = count * (0.35 + 0.65 * max / 255)
      total += base
      if (sat < 0.12) { weight[12] += base; next }
      delta = max - min
      if (max == r) hue = (g - b) / delta
      else if (max == g) hue = 2 + (b - r) / delta
      else hue = 4 + (r - g) / delta
      hue *= 60
      if (hue < 0) hue += 360
      bucket = int(hue / 30) % 12
      w = base * sat
      weight[bucket] += w
      red[bucket] += r * w; green[bucket] += g * w; blue[bucket] += b * w
    }
    /graya?\(/ {
      count = $1 + 0
      pixel = $0
      sub(/^.*graya?\(/, "", pixel)
      split(pixel, rgb, /[,)]/)
      total += count * (0.35 + 0.65 * channel(rgb[1]) / 255)
    }
    END {
      for (i = 0; i < 12; i++) {
        cluster = weight[(i + 11) % 12] + weight[i] + weight[(i + 1) % 12]
        if (cluster > best) { best = cluster; winner = i }
      }
      if (!best || best < total * 0.25) exit
      for (i = -1; i <= 1; i++) {
        bucket = (winner + i + 12) % 12
        rsum += red[bucket]; gsum += green[bucket]; bsum += blue[bucket]
      }
      r = rsum / best; g = gsum / best; b = bsum / best
      max = r > g ? r : g; max = max > b ? max : b
      min = r < g ? r : g; min = min < b ? min : b
      sat = (max - min) / max
      strength = sat * 2 < 1 ? sat * 2 : 1
      peak = int(255 * (0.35 + 0.45 * strength) + 0.5)
      printf "#%02x%02x%02x", int(r * peak / max + 0.5), int(g * peak / max + 0.5), int(b * peak / max + 0.5)
    }
  ' <<< "$histogram") || color=''
  if mkdir -p "$cache" 2>/dev/null; then
    printf '%s\n' "$color" > "$cache/$key" 2>/dev/null || :
  fi
  printf '%s\n' "$color"
}
