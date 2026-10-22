# tests/ytm/common.bash: shared setup, fakes and helpers of the ytm tests
setup() {
load ../helpers
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run" XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export FAKE="$BATS_TEST_TMPDIR/fake" OB_YTM_HELPER="$BATS_TEST_TMPDIR/bin/like-helper" OB_YTM_RETRY=0.1
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$FAKE/like"
  PATH="$BIN:$PATH"
  STATE="$XDG_RUNTIME_DIR/eww-island"; mkdir -p "$STATE"
  OUT="$BATS_TEST_TMPDIR/out" ERR="$BATS_TEST_TMPDIR/err"
  # ytm status prints $FAKE/status.N files once each in order, then $FAKE/status; ytm queue
  # prints the $FAKE/queue of call time after $FAKE/queue_delay seconds; other subcommands
  # are logged and exit with the code in $FAKE/rc.
  cat > "$BIN/ytm" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/ytm.log"
if [[ $1 == queue ]]; then
  q=$(cat "$FAKE/queue" 2>/dev/null) || exit 1
  sleep "$(cat "$FAKE/queue_delay" 2>/dev/null || echo 0)"
  printf '%s\n' "$q"
  exit 0
fi
if [[ $1 == status ]]; then
  for f in "$FAKE"/status.*; do
    [[ -e $f ]] || break
    cat "$f"; rm -f "$f"; exit 0
  done
  cat "$FAKE/status" 2>/dev/null || exit 1
  exit 0
fi
echo "Liked: something"
exit "$(cat "$FAKE/rc" 2>/dev/null || echo 0)"
EOF
  # The like helper answers "$FAKE/like/VID" = "DELAY STATUS".
  cat > "$BIN/like-helper" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$FAKE/helper.log"
read -r delay answer < "$FAKE/like/$1" || exit 1
sleep "$delay"
printf '%s\n' "$answer"
EOF
  chmod +x "$BIN/ytm" "$BIN/like-helper"
  source "$SCRIPTS/ytm"
}

teardown() {
  if [[ -n ${LISTENER:-} ]]; then kill "$LISTENER" 2>/dev/null; wait "$LISTENER" 2>/dev/null; fi
  return 0
}

INACTIVE='{"active":false,"video_id":"","like":"","next_title":"","next_artist":""}'

# st VID LIKE [NEXT_TITLE NEXT_ARTIST]: the listener line for an active track.
st() {
  printf '{"active":true,"video_id":"%s","like":"%s","next_title":"%s","next_artist":"%s"}' \
    "$1" "$2" "${3:-}" "${4:-}"
}

# queue INDEX [DELAY] "VID|TITLE|ARTIST"...: what `ytm queue` reports from now on.
queue() {
  local index=$1; shift
  if [[ $1 =~ ^[0-9.]+$ ]]; then printf '%s\n' "$1" > "$FAKE/queue_delay"; shift; fi
  printf '%s\n' "$@" | jq -Rnc --argjson i "$index" \
    '[inputs | split("|") | {video_id: .[0], title: .[1], artist: .[2], likeStatus: null}]
     | {tracks: ., current_index: $i, length: length, repeat: "off", shuffle: false}' > "$FAKE/queue.tmp"
  mv "$FAKE/queue.tmp" "$FAKE/queue"
}

# Q: a queue playing vidA0000001 at index 1 between two other tracks.
Q='{"tracks":[{"video_id":"vidZ0000000","title":"Song Z","artist":"Artist Z"},{"video_id":"vidA0000001","title":"Song A","artist":"Artist A"},{"video_id":"vidB0000002","title":"Song B","artist":"Artist B"}],"current_index":1,"length":3,"repeat":"off","shuffle":false}'

# play PLAYER TITLE [STATE]: write the island player state the way scripts/media does.
play() {
  printf '%s\n' "$1" > "$STATE/player"
  jq -nc --arg p "$1" --arg t "$2" --arg s "${3:-playing}" \
    '{state:$s,player:$p,title:$t,artist:"Artist",art:"",length:200,length_text:"3:20"}' > "$STATE/media.json.tmp"
  mv "$STATE/media.json.tmp" "$STATE/media.json"
}

# ytm_now VID TITLE: what `ytm status` reports from now on.
ytm_now() {
  jq -nc --arg v "$1" --arg t "$2" '{track:{video_id:$v,title:$t,artist:"Artist",likeStatus:null},is_playing:true}' > "$FAKE/status"
}

# answer VID STATUS [DELAY]: what the like helper returns for VID.
answer() { printf '%s %s\n' "${3:-0}" "$2" > "$FAKE/like/$1"; }

start() {
  "$SCRIPTS/ytm" > "$OUT" 2> "$ERR" 3>&- &
  LISTENER=$!
}

# wait_line JSON: wait up to 5 s for the listener to print exactly this line.
wait_line() {
  local i
  for ((i = 0; i < 100; i++)); do
    grep -qxF -- "$1" "$OUT" 2>/dev/null && return 0
    sleep 0.05
  done
  printf 'timed out waiting for %s; got:\n' "$1"; cat "$OUT"
  return 1
}

# wait_last JSON: wait up to 5 s for this to be the listener's latest line.
wait_last() {
  local i
  for ((i = 0; i < 100; i++)); do
    [[ $(tail -n 1 "$OUT" 2>/dev/null) == "$1" ]] && return 0
    sleep 0.05
  done
  printf 'timed out waiting for last line %s; got:\n' "$1"; cat "$OUT"
  return 1
}
