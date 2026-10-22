#!/usr/bin/env bash
# Alert source: sink volume and mute, microphone mute (pactl). Source it; do not execute.

ICON_VOL_MUTED=$'\U000F0581'
ICON_VOL_LOW=$'\uF026'
ICON_VOL_MID=$'\uF027'
ICON_VOL_HIGH=$'\uF028'
ICON_MIC=$'\U000F036C'
ICON_MIC_MUTED=$'\U000F036D'

audio_init() { alert_need pactl; }
audio_monitor() { printf '%s\0' pactl subscribe; }

audio_update() {
  local volume=$1 mute=$2 mic=$3 icon text
  if [[ -n ${audio_seen:-} ]]; then
    if [[ $volume != "$audio_volume" || $mute != "$audio_mute" ]]; then
      icon=$ICON_VOL_MUTED text=Bisu
      if [[ $mute == no ]]; then
        icon=$(level_icon "$volume" "$ICON_VOL_LOW" "$ICON_VOL_MID" "$ICON_VOL_HIGH")
        text=Volume
      fi
      alert_json volume "$icon" "$text" "$volume%" "$volume"
    fi
    if [[ $mic != "$audio_mic" ]]; then
      icon=$ICON_MIC text='Mikrofon nyala'
      if [[ $mic == yes ]]; then icon=$ICON_MIC_MUTED text='Mikrofon mati'; fi
      alert_json mic "$icon" "$text" '' -1
    fi
  fi
  audio_seen=1 audio_volume=$volume audio_mute=$mute audio_mic=$mic
}

audio_read() {
  local raw
  raw=$(pactl get-sink-volume @DEFAULT_SINK@) || return
  [[ $raw =~ ([0-9]+)% ]] || return 1
  sample_volume=$((10#${BASH_REMATCH[1]}))
  raw=$(pactl get-sink-mute @DEFAULT_SINK@) || return
  [[ $raw =~ Mute:[[:space:]]+(yes|no) ]] || return 1
  sample_mute=${BASH_REMATCH[1]}
  raw=$(pactl get-source-mute @DEFAULT_SOURCE@) || return
  [[ $raw =~ Mute:[[:space:]]+(yes|no) ]] || return 1
  sample_mic=${BASH_REMATCH[1]}
}

audio_snapshot() {
  audio_read || return
  audio_update "$sample_volume" "$sample_mute" "$sample_mic"
  # Source events cannot switch the output; older pactl without JSON keeps volume alerts.
  [[ ${1:-} == mic ]] || output_snapshot || :
}

audio_event() {
  local target
  case $1 in
    *' on sink #'*) target=volume ;;
    *' on source #'*) target=mic ;;
    *' on server'*) target=both ;;
    *) return 0 ;;
  esac
  audio_snapshot "$target" || return
  if [[ ${worker_mode:-0} == 1 ]]; then
    [[ $target == mic ]] || printf '@refresh volume\n'
    [[ $target == volume ]] || printf '@refresh mic\n'
  fi
}
