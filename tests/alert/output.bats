# tests/alert/output.bats
load helpers

@test "audio output switches emit the device with its icon and the port only for multi-port sinks" {
  make_fakes
  audio_snapshot > "$RESULT"
  {
    write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo analog-output-headphones
    audio_event "Event 'change' on sink #65"
    write_sinks alsa_output.pci-0000_01_00.1.hdmi-stereo
    audio_event "Event 'change' on server"
    write_sinks bluez_output.F4_93_B1_9A_5C_21.1
    audio_event "Event 'change' on server"
    write_sinks alsa_output.usb-Logitech_G435-00.analog-stereo
    audio_event "Event 'change' on server"
    write_sinks alsa_output.usb-Dock-00.analog-stereo
    audio_event "Event 'change' on server"
    write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
    audio_event "Event 'change' on server"
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["output","Output audio","Headphones",-1,""],["output","Output audio","Built-in Audio Digital Stereo (HDMI)",-1,""],["output","Output audio","WH-1000XM4",-1,""],["output","Output audio","G435 Wireless Gaming Headset Analog Stereo",-1,""],["output","Output audio","DisplayPort 1",-1,""],["output","Output audio","Speakers",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F02CB|\U000F0379|\U000F0970|\U000F02CB|\U000F0379|\U000F04C3' ]
}

@test "unchanged outputs stay silent and only sink or server events query the sinks once each" {
  make_fakes
  audio_snapshot > "$RESULT"
  : > "$ALERT_FIXTURE/audio-queries"
  {
    audio_event "Event 'change' on server"
    printf '51\n' > "$ALERT_FIXTURE/volume"
    audio_event "Event 'change' on sink #65"
    printf 'yes\n' > "$ALERT_FIXTURE/mic"
    audio_event "Event 'change' on source #66"
  } >> "$RESULT"
  [ "$(jq -sc 'map(.kind)' "$RESULT")" = '["volume","mic"]' ]
  [ "$(cat "$ALERT_FIXTURE/audio-queries")" = "$(printf '%s\n' \
    'get-sink-volume @DEFAULT_SINK@' 'get-sink-mute @DEFAULT_SINK@' 'get-source-mute @DEFAULT_SOURCE@' \
    get-default-sink '-f json list sinks' \
    'get-sink-volume @DEFAULT_SINK@' 'get-sink-mute @DEFAULT_SINK@' 'get-source-mute @DEFAULT_SOURCE@' \
    get-default-sink '-f json list sinks' \
    'get-sink-volume @DEFAULT_SINK@' 'get-sink-mute @DEFAULT_SINK@' 'get-source-mute @DEFAULT_SOURCE@')" ]
}

@test "audio monitor reconnect takes the output baseline silently" {
  make_fakes
  make_queued_monitor
  alert_source=audio source_stream queued_monitor "Event 'change' on server" > "$RESULT"
  write_sinks bluez_output.F4_93_B1_9A_5C_21.1
  alert_source=audio source_stream queued_monitor "Event 'change' on server" >> "$RESULT"
  [ ! -s "$RESULT" ]
  write_sinks alsa_output.pci-0000_00_1f.3.analog-stereo
  audio_event "Event 'change' on server" >> "$RESULT"
  [ "$(jq -c '[.kind,.value]' "$RESULT")" = '["output","Speakers"]' ]
}

@test "volume alerts keep working when pactl cannot list sinks as JSON" {
  make_fakes
  rm "$ALERT_FIXTURE/sinks.json"
  audio_snapshot > "$RESULT" 2>/dev/null
  printf '51\n' > "$ALERT_FIXTURE/volume"
  audio_event "Event 'change' on server" >> "$RESULT" 2>/dev/null
  [ "$(jq -c '[.kind,.value]' "$RESULT")" = '["volume","51%"]' ]
}
