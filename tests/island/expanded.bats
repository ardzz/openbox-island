# tests/island/expanded.bats
load ../helpers

@test "the expanded card grows in place instead of sliding down" {
  ! grep -q 'slidedown' "$REPO/eww/yuck/windows/expanded.yuck"
}
