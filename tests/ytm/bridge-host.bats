setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOST="$ROOT/eww/scripts/lib/ytm/bridge-host.sh"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  STATE="$XDG_RUNTIME_DIR/eww-island/ytm-browser.json"
}

frame() {
  python3 -c 'import struct, sys
for message in sys.argv[1:]:
    data = message.encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(data)) + data)' "$@"
}

host_messages() { frame "$@" | "$HOST"; }

@test "bridge host writes metadata and replaces the browser timestamp" {
  local before after
  before=$(date +%s%3N)
  run host_messages '{"title":"Lagu é","artist":"Artis","album":"Album","video_id":"abc","playing":true,"ts":1}'
  [ "$status" -eq 0 ]
  [ -f "$STATE" ]
  after=$(date +%s%3N)
  jq -e --argjson before "$before" --argjson after "$after" '
    .title == "Lagu é" and .artist == "Artis" and .album == "Album"
    and .video_id == "abc" and .playing == true
    and (.ts >= $before and .ts <= $after)' "$STATE"
}

@test "bridge host ignores malformed and invalid objects without changing previous state" {
  mkdir -p "${STATE%/*}"
  printf '%s\n' '{"title":"Lama","artist":"Artis","ts":2}' > "$STATE"
  local previous
  previous=$(cat "$STATE")
  run host_messages '{invalid' '[]' '{"title":3,"artist":"Artis"}' \
    '{"title":"Lagu"}' '{"title":"Lagu","artist":"Artis","ts":"bad"}'
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE")" = "$previous" ]
}

@test "bridge host keeps reading after invalid JSON and overwrites with the second valid message" {
  run host_messages '{"title":"Pertama","artist":"Artis"}' '{invalid' \
    '{"title":"Kedua","artist":"Baru","album":"Dua","video_id":"xyz","playing":false}'
  [ "$status" -eq 0 ]
  jq -e '.title == "Kedua" and .artist == "Baru" and .album == "Dua"
    and .video_id == "xyz" and .playing == false and (.ts | type == "number")' "$STATE"
}
