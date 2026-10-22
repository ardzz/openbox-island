# tests/viz/target.bats: which playback stream belongs to the active player
load common

@test "PID ancestry accepts the owner and a real owned child but rejects an ancestor" {
  local owner=$BASHPID
  sleep 30 &
  owned_child=$!
  run viz_descendant "$owner" "$owner"
  [ "$status" -eq 0 ]
  run viz_descendant "$owned_child" "$owner"
  [ "$status" -eq 0 ]
  run viz_descendant "$owner" "$owned_child"
  [ "$status" -eq 1 ]
}

@test "PID ancestry rejects invalid or missing processes" {
  local pid
  for pid in '' invalid 0 -1 999999999; do
    run viz_descendant "$pid" "$BASHPID"
    [ "$status" -eq 1 ]
    run viz_descendant "$BASHPID" "$pid"
    [ "$status" -eq 1 ]
  done
}

@test "stream selection prefers uncorked then numerically greatest serial among owned PIDs" {
  local owner=$BASHPID
  sleep 30 &
  owned_child=$!
  run viz_select "$owner" <<EOF
[
 {"index":1,"corked":false,"properties":{"application.process.id":"$owner","object.serial":"99"}},
 {"index":2,"corked":false,"properties":{"application.process.id":"$owned_child","object.serial":"100"}},
 {"index":3,"corked":true,"properties":{"application.process.id":"$owner","object.serial":"900"}},
 {"index":4,"corked":false,"properties":{"application.process.id":"$PPID","object.serial":"9999"}}
]
EOF
  [ "$status" -eq 0 ]
  [ "$output" = 100 ]
}

@test "corked owned streams remain eligible when none is uncorked" {
  run viz_select "$BASHPID" <<EOF
[
 {"index":1,"corked":true,"properties":{"application.process.id":"$BASHPID","object.serial":"9"}},
 {"index":2,"corked":true,"properties":{"application.process.id":"$BASHPID","object.serial":"10"}}
]
EOF
  [ "$status" -eq 0 ]
  [ "$output" = 10 ]
}

@test "unowned or malformed stream identities never become capture targets" {
  run viz_select "$BASHPID" <<EOF
[
 {"index":1,"corked":false,"properties":{"application.process.id":"$PPID","object.serial":"900"}},
 {"index":2,"corked":false,"properties":{"application.process.id":"$BASHPID","object.serial":"invalid"}},
 {"index":3,"corked":false,"properties":{"object.serial":"901"}}
]
EOF
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Streams without application.process.id resolve through their client's pid.
stub_clients() {
  export VIZ_TEST_CLIENTS=$1 VIZ_TEST_LOG="$BATS_TEST_TMPDIR/pactl.log"
  cat > "$BIN/pactl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VIZ_TEST_LOG"
[[ $* == '-f json list clients' ]] || exit 1
printf '%s\n' "$VIZ_TEST_CLIENTS"
EOF
  chmod +x "$BIN/pactl"
}

@test "a stream without its own pid is owned through its client's pipewire.sec.pid" {
  stub_clients "[
 {\"index\":41140,\"properties\":{\"pipewire.sec.pid\":\"$BASHPID\",\"application.process.id\":\"$BASHPID\"}},
 {\"index\":41150,\"properties\":{\"pipewire.sec.pid\":\"$BASHPID\"}}
]"
  run viz_select "$BASHPID" <<EOF
[
 {"index":41141,"client":"41140","corked":false,"properties":{"application.name":"mpv","object.serial":"41141"}},
 {"index":41151,"client":"41150","corked":true,"properties":{"object.serial":"99999"}},
 {"index":7,"corked":false,"properties":{"application.process.id":"$BASHPID","object.serial":"7"}}
]
EOF
  [ "$status" -eq 0 ]
  [ "$output" = 41141 ]
  [ "$(wc -l < "$VIZ_TEST_LOG")" -eq 1 ]
}

@test "client pid fallback uses application.process.id only without pipewire.sec.pid" {
  stub_clients "[{\"index\":12,\"properties\":{\"application.process.id\":\"$BASHPID\"}}]"
  run viz_select "$BASHPID" <<EOF
[{"index":13,"client":"12","corked":false,"properties":{"application.process.id":"invalid","object.serial":"13"}}]
EOF
  [ "$status" -eq 0 ]
  [ "$output" = 13 ]
}

@test "client pids of unrelated processes never make a stream a capture target" {
  stub_clients "[
 {\"index\":20,\"properties\":{\"pipewire.sec.pid\":\"$PPID\",\"application.process.id\":\"$PPID\"}},
 {\"index\":21,\"properties\":{\"pipewire.sec.pid\":\"$PPID\",\"application.process.id\":\"$BASHPID\"}},
 {\"index\":22,\"properties\":{\"pipewire.sec.pid\":\"invalid\"}},
 {\"index\":23,\"properties\":{\"pipewire.sec.pid\":\"$BASHPID\"}}
]"
  run viz_select "$BASHPID" <<EOF
[
 {"index":30,"client":"20","corked":false,"properties":{"object.serial":"30"}},
 {"index":31,"client":"21","corked":false,"properties":{"object.serial":"31"}},
 {"index":32,"client":"22","corked":false,"properties":{"object.serial":"32"}},
 {"index":33,"client":"404","corked":false,"properties":{"object.serial":"33"}},
 {"index":34,"client":"23","corked":false,"properties":{"application.process.id":"$PPID","object.serial":"34"}}
]
EOF
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "clients are not listed when every stream carries its own pid" {
  stub_clients '[]'
  run viz_select "$BASHPID" <<EOF
[{"index":1,"client":"9","corked":false,"properties":{"application.process.id":"$BASHPID","object.serial":"5"}}]
EOF
  [ "$output" = 5 ]
  [ ! -e "$VIZ_TEST_LOG" ]
}

@test "target resolution uses the active MPRIS instance DBus owner and owned stream serial" {
  stub_target_tools
  run viz_target edge.known
  [ "$status" -eq 0 ]
  [ "$output" = 321 ]
  run viz_target edge.unknown
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
