# tests/viz/cava.bats: CAVA frames and the visualizer frame rate
load common

@test "six raw CAVA levels 0-12 become newline-delimited JSON including silence" {
  run viz_frames <<'EOF'
0;1;2;6;7;8;
9;10;11;12;12;0;
12;11;10;9;8;7;
0;0;0;0;0;0;
EOF
  [ "$status" -eq 0 ]
  [ "$output" = $'[0,1,2,6,7,8]\n[9,10,11,12,12,0]\n[12,11,10,9,8,7]\n[0,0,0,0,0,0]' ]
}

@test "malformed CAVA frames are dropped whole without poisoning the next frame" {
  run viz_frames <<'EOF'
0;1;2;3;4;
0;1;2;3;4;5;6;
0;1;2;3;4;13;
0;1;2;3;4;99;
0;1;2;3;4;120;
0;1;2;3;4;-1;
0;1;2;3;4;08;
0;1;2;3;4;012;
0;1;2;3;4;x;
0;1;2;3;4;5
0;1;2;3;4;5;garbage

1;2;3;4;5;6;
EOF
  [ "$status" -eq 0 ]
  [ "$output" = '[1,2,3,4,5,6]' ]
}

@test "visualizer fps follows the current mode of the origin monitor" {
  stub_xrandr "${laptop_144[@]}"
  run viz_fps
  [ "$status" -eq 0 ]
  [ "$output" = 144 ]
  stub_xrandr 'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767' \
    'eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm' \
    '   1920x1080     60.00*+  48.00  '
  run viz_fps
  [ "$output" = 60 ]
}

@test "fractional refresh rates round to the nearest integer fps" {
  stub_xrandr 'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767' \
    'DP-2 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 527mm x 296mm' \
    '   1920x1080     60.00 +  59.94*   50.00  '
  run viz_fps
  [ "$output" = 60 ]
  stub_xrandr 'DP-2 connected 1920x1080+0+0 (normal) 527mm x 296mm' '   1920x1080    143.50*'
  run viz_fps
  [ "$output" = 144 ]
}

@test "an external monitor listed first does not override the origin monitor" {
  stub_xrandr 'Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767' \
    'HDMI-1 connected 2560x1440+1920+0 (normal left inverted right x axis y axis) 597mm x 336mm' \
    '   2560x1440     59.95 +  74.97*  ' \
    '   1920x1080     60.00    50.00  ' \
    'eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm' \
    '   1920x1080    144.00 +  120.00*  '
  run viz_fps
  [ "$output" = 120 ]
}

@test "the primary monitor is used when no output sits at the screen origin" {
  stub_xrandr 'Screen 0: minimum 8 x 8, current 4480 x 2520, maximum 32767 x 32767' \
    'HDMI-1 connected 2560x1440+1920+0 (normal) 597mm x 336mm' \
    '   2560x1440     74.97*  ' \
    'eDP-1 connected primary 1920x1080+0+1440 (normal) 344mm x 194mm' \
    '   1920x1080    165.00*+  '
  run viz_fps
  [ "$output" = 165 ]
}

@test "refresh rates beyond 240 Hz clamp to 240 fps" {
  stub_xrandr 'DP-1 connected 1920x1080+0+0 (normal) 527mm x 296mm' '   1920x1080    360.00*+'
  run viz_fps
  [ "$output" = 240 ]
}

@test "ISLAND_VIZ_FPS overrides the monitor when it is an integer from 1 to 240" {
  local fps
  stub_xrandr "${laptop_144[@]}"
  for fps in 1 75 240; do
    ISLAND_VIZ_FPS=$fps run viz_fps
    [ "$output" = "$fps" ]
  done
}

@test "invalid ISLAND_VIZ_FPS is ignored in favour of the monitor rate" {
  local fps
  stub_xrandr "${laptop_144[@]}"
  for fps in '' 0 241 -5 60.5 abc 0x3c 060; do
    ISLAND_VIZ_FPS=$fps run viz_fps
    [ "$output" = 144 ]
  done
}

@test "fps falls back to 60 without a usable display or xrandr" {
  stub_xrandr "${laptop_144[@]}"
  run bash -c 'unset DISPLAY; source "$1"; viz_fps' _ "$SCRIPTS/viz"
  [ "$output" = 60 ]
  stub_xrandr 'Screen 0: garbage' 'eDP-1 connected 1920x1080+0+0' '   1920x1080    fast*'
  run viz_fps
  [ "$output" = 60 ]
  rm "$BATS_TEST_TMPDIR/xrandr.out"
  run viz_fps
  [ "$output" = 60 ]
  rm "$BIN/xrandr"
  run bash -c 'source "$1"; PATH=$2; viz_fps' _ "$SCRIPTS/viz" "$BIN"
  [ "$output" = 60 ]
}
