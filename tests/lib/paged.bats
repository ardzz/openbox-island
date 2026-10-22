# tests/lib/paged.bats
setup() {
  load ../helpers
  source "$SCRIPTS/lib/core.sh"
  source "$SCRIPTS/lib/paged.sh"
  TEN=$(jq -nc '[range(10)]')
}

@test "first page of ten" {
  run paged "$TEN" 0 4
  [ "$status" -eq 0 ]
  [ "$output" = '{"rows":[0,1,2,3],"more":6,"offset":0}' ]
}

@test "an offset past the end shows the last full page" {
  run paged "$TEN" 9 4
  [ "$output" = '{"rows":[6,7,8,9],"more":0,"offset":6}' ]
}

@test "a negative offset clamps to zero" {
  run paged "$TEN" -2 4
  [ "$output" = '{"rows":[0,1,2,3],"more":6,"offset":0}' ]
}

@test "a list shorter than a page always starts at zero" {
  run paged '[0,1,2]' 1 4
  [ "$output" = '{"rows":[0,1,2],"more":0,"offset":0}' ]
}

@test "an empty list gives an empty page" {
  run paged '[]' 3 4
  [ "$output" = '{"rows":[],"more":0,"offset":0}' ]
}
