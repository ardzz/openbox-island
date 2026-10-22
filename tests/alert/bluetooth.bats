# tests/alert/bluetooth.bats
load helpers

@test "bluetooth connection changes emit per device with alias battery and device icon" {
  make_fakes
  bluetooth_snapshot > "$RESULT"
  {
    bluetooth_event "$(bt_line AA_BB_CC_DD_EE_01 Device1 "'Connected': <true>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'ServicesResolved': <true>, 'Connected': <true>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'Connected': <true>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'Connected': <false>, 'ServicesResolved': <false>")"
    bluetooth_event "$(bt_line AA_BB_CC_DD_EE_01 Device1 "'Connected': <false>")"
    bluetooth_event "$(bt_line AA_BB_CC_DD_EE_01 Device1 "'Connected': <false>")"
  } >> "$RESULT"
  [ "$(jq -sc 'map([.kind,.text,.value,.level,.image])' "$RESULT")" = '[["bluetooth","Bluetooth tersambung","WH-1000XM4 · 80%",-1,""],["bluetooth","Bluetooth terputus","WH-1000XM4",-1,""],["bluetooth","Bluetooth terputus","Keyboard K380",-1,""]]' ]
  [ "$(jq -sr 'map(.icon)|join("|")' "$RESULT")" = $'\U000F02CB|\U000F02CB|\U000F030C' ]
}

@test "bluetooth ignores signals other than a device Connected change without querying" {
  make_fakes
  bluetooth_snapshot > "$RESULT"
  {
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Device1 "'RSSI': <int16 -60>")"
    bluetooth_event "$(bt_line F4_93_B1_9A_5C_21 Battery1 "'Percentage': <byte 0x4f>")"
    bluetooth_event "/org/bluez/hci0/dev_F4_93_B1_9A_5C_21/sep1/fd0: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.MediaTransport1', {'State': <'active'>}, @as [])"
    bluetooth_event "/org/bluez/hci0: org.freedesktop.DBus.Properties.PropertiesChanged ('org.bluez.Adapter1', {'Discovering': <true>}, @as [])"
    bluetooth_event 'Monitoring signals from all objects owned by org.bluez'
  } >> "$RESULT"
  [ ! -s "$RESULT" ]
  [ "$(cat "$ALERT_FIXTURE/bt-queries")" = 'devices Connected' ]
}

@test "bluetooth icons map audio gaming mouse keyboard and phone devices with a bluetooth fallback" {
  make_fakes
  bluetooth_snapshot > /dev/null
  local icon
  for icon in audio-headphones audio-headset audio-card input-gaming input-mouse input-keyboard phone computer ''; do
    {
      printf 'Device 11:22:33:44:55:66 (public)\n\tAlias: Perangkat\n'
      [[ -z $icon ]] || printf '\tIcon: %s\n' "$icon"
    } > "$ALERT_FIXTURE/bt-info-11:22:33:44:55:66"
    bluetooth_event "$(bt_line 11_22_33_44_55_66 Device1 "'Connected': <true>")"
    bluetooth_event "$(bt_line 11_22_33_44_55_66 Device1 "'Connected': <false>")"
  done > "$RESULT"
  [ "$(jq -sr 'map(select(.text == "Bluetooth tersambung") | .icon)|join("|")' "$RESULT")" = $'\U000F02CB|\U000F02CB|\U000F02CB|\U000F0297|\U000F037D|\U000F030C|\U000F011C|\U000F00AF|\U000F00AF' ]
  [ "$(jq -sc 'map(.value)|unique' "$RESULT")" = '["Perangkat"]' ]
}
