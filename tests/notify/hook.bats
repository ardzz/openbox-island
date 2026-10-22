load ../helpers
load common
bats_require_minimum_version 1.5.0

@test "hook writes one JSON line per notification to the listener fifo" {
  mkfifo "$FIFO"
  exec {reader}<> "$FIFO"
  post 571 'Rapat' 'Mulai sebentar lagi' CRITICAL Thunderbird /usr/share/icons/x.png org.mozilla.thunderbird tagz
  IFS= read -r -t 1 -u "$reader" line
  [ "$(jq -c '[.id,.app,.summary,.body,.icon,.urgency,.entry,.tag]' <<< "$line")" = '[571,"Thunderbird","Rapat","Mulai sebentar lagi","/usr/share/icons/x.png","CRITICAL","org.mozilla.thunderbird","tagz"]' ]
}

@test "hook flattens control characters and truncates fields to one atomic pipe write" {
  mkfifo "$FIFO"
  exec {reader}<> "$FIFO"
  local body summary
  printf -v body '%.0s"é\\\t\n' {1..3000}
  printf -v summary '%.0s<b>' {1..1000}
  post 9 "$summary" "$body" NORMAL "$summary" "/icons/$body" "$summary" "$summary"
  IFS= read -r -t 1 -u "$reader" line
  if IFS= read -r -t 0.05 -u "$reader" extra; then false; fi
  jq -e . <<< "$line" > /dev/null
  [ "$(LC_ALL=C; printf '%s' "${#line}")" -lt 4096 ]
  [ "$(jq -r '.body | test("[\n\t]")' <<< "$line")" = false ]
  [[ $(jq -r .body <<< "$line") == '"é\  "é\'* ]]
}

@test "hook exits quietly without a running listener" {
  run timeout 2 env DUNST_ID=1 DUNST_SUMMARY=x "$SCRIPTS/notify-hook"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$FIFO" ]
}

@test "hook never blocks on a fifo nobody reads" {
  mkfifo "$FIFO"
  run timeout 2 env DUNST_ID=1 DUNST_SUMMARY=x "$SCRIPTS/notify-hook"
  [ "$status" -eq 0 ]
}
