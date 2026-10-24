# tests/prep/common.bash: setup and helpers shared by tests/prep/*.bats.
load ../helpers

setup() {
  export TZ=Asia/Jakarta
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config" XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export ISLAND_PREP="$BATS_TEST_TMPDIR/prep-file"
  unset ISLAND_PREP_BEFORE ISLAND_DEADLINE_TIME
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/todo/deadline.sh"
  source "$SCRIPTS/lib/prep/template.sh"
  START=$(date -d '2026-10-22 10:00' +%s) # Thu 22 Oct 10:00
  NOW=1792551600 # Wed 2026-10-21 10:00
}

# prep_write LINES...: write LINES to the template file (no lines = missing file).
prep_write() {
  if (( $# )); then printf '%s\n' "$@" > "$ISLAND_PREP"; else rm -f "$ISLAND_PREP"; fi
}
