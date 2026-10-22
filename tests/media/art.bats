# tests/media/art.bats: cover art resolution and its cache
load common

@test "a cover path that would break CSS is served through a safe cache link" {
  touch "$BATS_TEST_TMPDIR/album's cover.jpg"
  run resolve_art "file://$BATS_TEST_TMPDIR/album%27s%20cover.jpg"
  [ "$status" -eq 0 ]
  [[ $output == "$ART_CACHE/"* ]]
  [[ $output != *"'"* ]]
  [ "$(readlink "$output")" = "$BATS_TEST_TMPDIR/album's cover.jpg" ]
}

@test "an http cover is served from cache without downloading again" {
  url='https://lh3.googleusercontent.com/abc=w120'
  file="$ART_CACHE/$(printf '%s' "$url" | sha1sum | cut -c1-40)"
  mkdir -p "$ART_CACHE"; printf 'img' > "$file"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/curl.log"\nexit 22\n' "$BATS_TEST_TMPDIR" > "$BIN/curl"; chmod +x "$BIN/curl"
  run resolve_art "$url"
  [ "$output" = "$file" ]
  [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "an http cover is downloaded once into the cache" {
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
while (( $# )); do if [[ $1 == -o ]]; then printf 'img' > "$2"; fi; shift; done
EOF
  chmod +x "$BIN/curl"
  run resolve_art 'https://example.invalid/cover.jpg'
  [ "$status" -eq 0 ]
  [[ $output == "$ART_CACHE/"* ]]
  [ "$(cat "$output")" = img ]
}

@test "a failed download leaves no cover and no partial file" {
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
while (( $# )); do if [[ $1 == -o ]]; then printf 'half' > "$2"; fi; shift; done
exit 28
EOF
  chmod +x "$BIN/curl"
  run resolve_art 'https://example.invalid/x.jpg'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ -z "$(find "$ART_CACHE" -type f 2>/dev/null)" ]
}

@test "missing local artwork returns no cover and creates no alias" {
  run resolve_art "file://$BATS_TEST_TMPDIR/missing%27s.jpg"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ ! -d "$ART_CACHE" ]
}
