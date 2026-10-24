# tests/prep/common.bash: setup and helpers shared by tests/prep/*.bats.
load ../helpers

setup() {
  export TZ=Asia/Jakarta
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export ISLAND_PREP="$BATS_TEST_TMPDIR/prep-file"
  export ISLAND_NOW=1792551600 # Wed 2026-10-21 10:00
  unset ISLAND_PREP_BEFORE ISLAND_DEADLINE_TIME ISLAND_PREP_AHEAD ISLAND_PREP_INTERVAL
  unset ISLAND_DEADLINE_EVE ISLAND_DEADLINE_DAY
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/store.sh"
  source "$SCRIPTS/lib/todo/data.sh"
  source "$SCRIPTS/lib/todo/deadline.sh"
  source "$SCRIPTS/lib/prep/template.sh"
  [[ ! -f $SCRIPTS/lib/prep/sync.sh ]] || source "$SCRIPTS/lib/prep/sync.sh"
  ST="$ISLAND_STATE"
  export FIX="$BATS_TEST_TMPDIR"
  BIN="$BATS_TEST_TMPDIR/bin"
  export EXPECTED_CFG="$REPO/eww"
  mkdir -p "$ST" "${TODO_FILE%/*}" "$BIN"
  : > "$FIX/calls"
  printf 'island: island\n' > "$FIX/active"
  cat > "$BIN/eww" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == --config && $2 == "$EXPECTED_CFG" ]]; then shift 2; else echo "bad config: $*" >> "$FIX/calls"; exit 1; fi
case $1 in
  active-windows) cat "$FIX/active"; exit 0 ;;
  get) exit 0 ;;
esac
printf 'eww %s\n' "$*" >> "$FIX/calls"
EOF
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$BIN/rofi" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'rofi %s\n' "$*" >> "$FIX/calls"
[[ -s $FIX/rofi_answers ]] || exit 1
head -n 1 "$FIX/rofi_answers"
sed -i 1d "$FIX/rofi_answers"
EOF
  cat > "$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BIN/eww" "$BIN/xdotool" "$BIN/rofi" "$BIN/sleep"
  export PATH="$BIN:$PATH"
  START=$(date -d '2026-10-22 10:00' +%s) # Thu 22 Oct 10:00
  NOW=1792551600 # Wed 2026-10-21 10:00
}

# answer TEXT: queue TEXT as the next fake-rofi answer (an empty line answers empty).
answer() { printf '%s\n' "$1" >> "$FIX/rofi_answers"; }

# expanded_card: the expanded island counts as open for island dismiss.
expanded_card() { printf 'island: island\nisland-expanded: island-expanded\n' > "$FIX/active"; }

# prep_write LINES...: write LINES to the template file (no lines = missing file).
prep_write() {
  if (( $# )); then printf '%s\n' "$@" > "$ISLAND_PREP"; else rm -f "$ISLAND_PREP"; fi
}

# at TIME: epoch of a local "YYYY-MM-DD HH:MM" string.
at() { date -d "$1" +%s; }

# template_weekly: the Weekly Report template used by the sync tests.
template_weekly() { prep_write 'Weekly Report | 2j | Report progres; Plan minggu depan'; }

# row ID TITLE START: one agenda row as JSON (id must be 12 hex chars).
row() { jq -nc --arg id "$1" --arg title "$2" --argjson start "$3" '{id:$id,start:$start,title:$title}'; }

# agenda_rows ROWS_JSON [OK]: write agenda.json with the given rows (default ok:true).
agenda_rows() {
  jq -nc --argjson rows "[$1]" --argjson ok "${2:-true}" \
    '{ok:$ok,stale:false,updated:"09:55",error:"",label:"Kalender",remaining:1,allday:[],next:null,errors:[],rows:$rows}' \
    > "$ST/agenda.json"
}

# items_json: todo items without ids, for exact comparison.
items_json() { jq -c '[.items[] | {text,done,due,reminded,prep}]' "$TODO_FILE"; }

# many_items N: "i1; i2; ...; iN" (long template item lists).
many_items() {
  local s='' i
  for (( i = 1; i <= $1; i++ )); do s+="i$i; "; done
  printf '%s' "${s%; }"
}
