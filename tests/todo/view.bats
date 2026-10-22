load ../helpers
load common
bats_require_minimum_version 1.5.0

@test "at most four rows show and the rest count as +N" {
  add_all 1 2 3 4 5 6
  start_listener
  [ "$(texts)" = '["6","5","4","3"]' ]
  [ "$(jq -c '[.more,.offset]' <<< "$event")" = '[2,0]' ]
}

@test "scrolling pages through the rows and stops at both ends" {
  add_all 1 2 3 4 5 6
  start_listener
  todo scroll down; next_event
  [ "$(texts)" = '["5","4","3","2"]' ]
  [ "$(jq -c '[.more,.offset]' <<< "$event")" = '[1,1]' ]
  todo scroll down; next_event
  [ "$(texts)" = '["4","3","2","1"]' ]
  todo scroll down
  quiet 0.3
  todo scroll up; next_event
  todo scroll up; next_event
  [ "$(jq .offset <<< "$event")" -eq 0 ]
  todo scroll up
  quiet 0.3
}

@test "a short list never scrolls" {
  add_all 1 2 3
  start_listener
  todo scroll down
  quiet 0.3
}

@test "removing items pulls the scroll offset back into range" {
  add_all 1 2 3 4 5 6
  start_listener
  todo scroll down; next_event
  todo scroll down; next_event
  todo remove "$(id_of 1)"; next_event
  [ "$(jq -c '[.offset,.more]' <<< "$event")" = '[1,0]' ]
  [ "$(texts)" = '["5","4","3","2"]' ]
}

@test "collapsing the island scrolls the list back to the top" {
  add_all 1 2 3 4 5
  start_listener
  todo scroll down; next_event
  signal '@expanded 0'
  next_event
  [ "$(jq .offset <<< "$event")" -eq 0 ]
}

@test "the listener emits once after every command and idles otherwise" {
  start_listener
  todo add a; next_event
  [ "$(texts)" = '["a"]' ]
  todo toggle "$(id_of a)"; next_event
  [ "$(done_flags)" = '[true]' ]
  todo toggle "$(id_of a)"; next_event
  [ "$(done_flags)" = '[false]' ]
  todo toggle "$(id_of a)"; next_event
  todo clear-done; next_event
  [ "$(texts)" = '[]' ]
  todo add b; next_event
  todo remove "$(id_of b)"; next_event
  [ "$(texts)" = '[]' ]
  quiet 0.5
}
