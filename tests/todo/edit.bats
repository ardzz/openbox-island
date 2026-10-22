load ../helpers
load common
bats_require_minimum_version 1.5.0

@test "a missing list shows an empty tab labelled Tugas" {
  start_listener
  [ "$(jq -c '[.open,.label,.rows,.more,.offset]' <<< "$event")" = '[0,"Tugas",[],0,0]' ]
}

@test "add stores trimmed text in the data dir and the label counts open items" {
  start_listener
  run todo add '   beli susu  '
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["beli susu"]' ]
  [ "$(done_flags)" = '[false]' ]
  [ "$(jq -c '[.open,.label]' <<< "$event")" = '[1,"Tugas 1"]' ]
  [ -s "$DATA" ]
}

@test "add flattens line breaks and tabs into single spaces" {
  todo add $'bayar\n\tlistrik   dan  air'
  start_listener
  [ "$(texts)" = '["bayar listrik dan air"]' ]
}

@test "add rejects empty or whitespace-only text and leaves the list alone" {
  todo add satu
  run todo add ''
  [ "$status" -ne 0 ]
  run todo add $'   \n\t '
  [ "$status" -ne 0 ]
  run todo add
  [ "$status" -ne 0 ]
  start_listener
  [ "$(texts)" = '["satu"]' ]
}

@test "open items come first, newest first; done items follow, latest finished first" {
  add_all a b c d
  start_listener
  [ "$(texts)" = '["d","c","b","a"]' ]
  todo toggle "$(id_of a)"; next_event
  todo toggle "$(id_of c)"; next_event
  [ "$(texts)" = '["d","b","c","a"]' ]
  [ "$(done_flags)" = '[false,false,true,true]' ]
  [ "$(jq -r .label <<< "$event")" = 'Tugas 2' ]
}

@test "toggling a done item reopens it in its place among the open ones" {
  add_all a b c
  start_listener
  todo toggle "$(id_of b)"; next_event
  [ "$(texts)" = '["c","a","b"]' ]
  todo toggle "$(id_of b)"; next_event
  [ "$(texts)" = '["c","b","a"]' ]
  [ "$(jq -c '[.open,.label]' <<< "$event")" = '[3,"Tugas 3"]' ]
}

@test "the label drops the count once everything is done" {
  todo add a
  start_listener
  todo toggle "$(id_of a)"; next_event
  [ "$(jq -c '[.open,.label]' <<< "$event")" = '[0,"Tugas"]' ]
}

@test "remove deletes one item by id" {
  add_all a b c
  start_listener
  run todo remove "$(id_of b)"
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["c","a"]' ]
}

@test "unknown ids change nothing and malformed ids are usage errors" {
  add_all a
  start_listener
  run todo toggle 999
  [ "$status" -eq 1 ]
  run todo remove 999
  [ "$status" -eq 1 ]
  run todo toggle abc
  [ "$status" -eq 2 ]
  run todo remove ''
  [ "$status" -eq 2 ]
  quiet 0.3
  stop_listener; start_listener
  [ "$(texts)" = '["a"]' ]
  [ "$(done_flags)" = '[false]' ]
}

@test "ids are never reused after a removal" {
  add_all a b
  start_listener
  local old
  old=$(id_of b)
  todo remove "$old"; next_event
  todo add c; next_event
  [ "$(id_of c)" != "$old" ]
}

@test "clear-done removes only finished items" {
  add_all a b c
  start_listener
  todo toggle "$(id_of a)"; next_event
  todo toggle "$(id_of c)"; next_event
  run todo clear-done
  [ "$status" -eq 0 ]
  next_event
  [ "$(texts)" = '["b"]' ]
}

@test "the list survives a listener restart and is read from the data file" {
  add_all a b
  start_listener
  todo toggle "$(id_of a)"; next_event
  stop_listener
  start_listener
  [ "$(texts)" = '["b","a"]' ]
  [ "$(done_flags)" = '[false,true]' ]
}

@test "a corrupt list reads as empty and is kept aside on the next write" {
  mkdir -p "${DATA%/*}"
  printf 'not json\n' > "$DATA"
  start_listener
  [ "$(jq -c '[.open,.rows]' <<< "$event")" = '[0,[]]' ]
  todo add baru
  next_event
  [ "$(texts)" = '["baru"]' ]
  [ "$(cat "$DATA.corrupt")" = 'not json' ]
}

@test "a list of the wrong shape reads as empty and is kept aside on the next write" {
  mkdir -p "${DATA%/*}"
  printf '{"next_id":3,"items":[{"id":1,"text":"x","done":"no"}]}\n' > "$DATA"
  start_listener
  [ "$(jq -c '[.open,.rows]' <<< "$event")" = '[0,[]]' ]
  todo add baru
  next_event
  [ "$(texts)" = '["baru"]' ]
  [ "$(jq -c '.items[0].done' "$DATA.corrupt")" = '"no"' ]
  [ "$(jq -c '[.next_id,[.items[].id]]' "$DATA")" = '[2,[1]]' ]
}

@test "concurrent adds all land with distinct ids and leave no temp files" {
  local i
  for i in 1 2 3 4 5 6 7 8; do todo add "t$i" & done
  wait
  start_listener
  [ "$(jq '.rows | length' <<< "$event")" -eq 4 ]
  [ "$(jq .open <<< "$event")" -eq 8 ]
  [ "$(jq '.more' <<< "$event")" -eq 4 ]
  [ "$(ls -A "${DATA%/*}" | grep -cv '^todo\.json\(\.lock\)\?$')" -eq 0 ]
  [ "$(jq '[.rows[].id] | unique | length' <<< "$event")" -eq 4 ]
  # Distinct ids: finishing the four shown rows leaves exactly four open.
  local id
  for id in $(jq -r '.rows[].id' <<< "$event"); do todo toggle "$id"; next_event; done
  [ "$(jq .open <<< "$event")" -eq 4 ]
}

@test "commands work while no listener runs" {
  run todo add a
  [ "$status" -eq 0 ]
  [ ! -e "$FIFO" ]
  start_listener
  [ "$(texts)" = '["a"]' ]
}

@test "unknown commands and scroll directions are usage errors" {
  run todo explode
  [ "$status" -eq 2 ]
  run todo scroll left
  [ "$status" -eq 2 ]
  [ ! -e "$DATA" ]
}
