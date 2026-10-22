# tests/tools/check.bats
setup() {
  CHECK="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tools/check"
  FIX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIX/eww/scripts" "$FIX/tests" "$FIX/docs"
  git -C "$FIX" init -q
}

# lines FILE N: write N short lines to FIX/FILE.
lines() { mkdir -p "$(dirname "$FIX/$1")"; seq "$2" | sed 's/^/# /' > "$FIX/$1"; }

track() { git -C "$FIX" add -A; }

@test "a clean tree passes silently" {
  printf '#!/usr/bin/env bash\necho hi\n' > "$FIX/eww/scripts/ok"
  printf 'print("hi")\n' > "$FIX/eww/scripts/ok.py"
  track
  run "$CHECK" "$FIX"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a file over 200 lines warns but passes" {
  lines eww/long.yuck 250; track
  run "$CHECK" "$FIX"
  [ "$status" -eq 0 ]
  [[ $output == *"WARN eww/long.yuck 250 baris"* ]]
}

@test "a file over 300 lines fails" {
  lines tests/huge.bats 301; track
  run "$CHECK" "$FIX"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL tests/huge.bats 301 baris"* ]]
}

@test "a shellcheck warning fails, by shebang or by .sh" {
  printf '#!/usr/bin/env bash\ncd /tmp\n' > "$FIX/eww/scripts/nocheck"; track
  run "$CHECK" "$FIX"
  [ "$status" -eq 1 ]
  [[ $output == *"eww/scripts/nocheck"* ]]
  git -C "$FIX" rm -q -f eww/scripts/nocheck; mkdir -p "$FIX/eww"
  printf 'cd /tmp || exit\nunused=1\n' > "$FIX/eww/lib.sh"
  printf 'cd /tmp\n' > "$FIX/eww/plain.txt"; track
  run "$CHECK" "$FIX"
  [ "$status" -eq 1 ]
  [[ $output == *"eww/lib.sh"* ]]
  [[ $output != *"plain.txt"* ]]
}

@test "shellcheck notes below warning severity pass" {
  printf '#!/usr/bin/env bash\necho $1\n' > "$FIX/eww/scripts/quote"; track
  run "$CHECK" "$FIX"
  [ "$status" -eq 0 ]
}

@test "a broken python file fails" {
  printf 'def broken(:\n' > "$FIX/eww/scripts/bad.py"; track
  run "$CHECK" "$FIX"
  [ "$status" -eq 1 ]
  [[ $output == *"bad.py"* ]]
  [ ! -e "$FIX/eww/scripts/__pycache__" ]
}

@test "excluded, untracked and out-of-scope files are ignored" {
  lines eww/cava.conf 400
  lines eww/players 400
  lines eww/shortcuts 400
  lines docs/notes.txt 400
  head -c 20000 /dev/urandom > "$FIX/eww/cover.png"
  track
  lines eww/untracked.yuck 400
  printf 'def broken(:\n' > "$FIX/eww/stray.py"
  run "$CHECK" "$FIX"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the root defaults to the repo holding the script" {
  mkdir -p "$FIX/tools"; cp "$CHECK" "$FIX/tools/check"
  lines eww/huge.yuck 301; track
  run "$FIX/tools/check"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL eww/huge.yuck 301 baris"* ]]
}
