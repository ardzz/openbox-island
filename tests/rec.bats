load helpers

setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export ISLAND_PROC="$BATS_TEST_TMPDIR/proc"
  mkdir -p "$XDG_RUNTIME_DIR" "$ISLAND_PROC"
  source "$SCRIPTS/rec"
  IDLE='{"active":false,"app":"","time":""}'
}

teardown() {
  if [[ -n ${listener_pid:-} ]]; then
    kill "$listener_pid" 2>/dev/null || :
    wait "$listener_pid" 2>/dev/null || :
  fi
}

# fake_proc PID COMM [ARGV...]: a fake /proc entry owned by the test user.
fake_proc() {
  local pid=$1 comm=$2
  shift 2
  mkdir -p "$ISLAND_PROC/$pid/fd" "$ISLAND_PROC/$pid/fdinfo"
  printf '%s\n' "$comm" > "$ISLAND_PROC/$pid/comm"
  if (( $# )); then printf '%s\0' "$@" > "$ISLAND_PROC/$pid/cmdline"; else : > "$ISLAND_PROC/$pid/cmdline"; fi
}

# fake_fd PID FD TARGET OCTAL_FLAGS: an open descriptor and its fdinfo.
fake_fd() {
  ln -s "$3" "$ISLAND_PROC/$1/fd/$2"
  printf 'pos:\t0\nflags:\t%s\nmnt_id:\t25\nino:\t1234\n' "$4" > "$ISLAND_PROC/$1/fdinfo/$2"
}

@test "ffmpeg counts as recording only when its input format is x11grab or kmsgrab" {
  fake_proc 100 ffmpeg ffmpeg -i in.mkv -c:v libx264 out.mp4
  fake_proc 101 bash bash -c 'ffmpeg -f x11grab'
  fake_proc 104 ffmpeg ffmpeg -i kmsgrab-demo.mkv out.mp4
  fake_proc 105 ffmpeg ffmpeg -i x11grab.mp4 -f mp4 out.mp4
  fake_proc 106 ffmpeg ffmpeg -i in.mkv -metadata title=-f out.mkv x11grab.mkv
  rec_detect
  [ "$rec_app" = '' ]
  fake_proc 102 ffmpeg ffmpeg -video_size 1920x1080 -f x11grab -i :0.0 /tmp/layar.mp4
  rec_detect
  [ "$rec_app" = ffmpeg ]
  rm -r "${ISLAND_PROC:?}/102"
  fake_proc 103 ffmpeg ffmpeg -device /dev/dri/card0 -f kmsgrab -i - out.mkv
  rec_detect
  [ "$rec_app" = ffmpeg ]
}

# fake_obs PID: an idle OBS parent holding only logs, a GPU node and a read-only clip.
fake_obs() {
  fake_proc "$1" obs obs
  fake_fd "$1" 3 /home/user/.config/obs-studio/logs/2026-10-22.txt 0102001
  fake_fd "$1" 4 /home/user/Videos/lama.mp4 0100000
  fake_fd "$1" 5 /dev/dri/renderD128 0102002
}

@test "obs recording is seen through its obs-ffmpeg-mux helper writing the video file" {
  fake_obs 200
  fake_proc 201 obs-ffmpeg-mux /usr/bin/obs-ffmpeg-mux 1 2 3
  fake_fd 201 0 'pipe:[51234]' 0100000
  fake_fd 201 4 /home/user/Videos/lama.mp4 0100000
  rec_detect
  [ "$rec_app" = '' ]
  fake_fd 201 6 '/home/user/Videos/2026-10-22 10-00-00.mkv' 0101001
  rec_detect
  [ "$rec_app" = OBS ]
  rm "$ISLAND_PROC/201/fd/6"
  fake_fd 201 7 /home/user/Videos/stream.webm 0100002
  rec_detect
  [ "$rec_app" = OBS ]
}

@test "obs writing a video file itself also counts as recording" {
  fake_obs 210
  rec_detect
  [ "$rec_app" = '' ]
  fake_fd 210 6 /home/user/Videos/rekaman.mov 0101001
  rec_detect
  [ "$rec_app" = OBS ]
}

@test "other processes writing video files are not screen recordings" {
  fake_proc 300 firefox firefox
  fake_fd 300 9 /home/user/Downloads/video.mp4 0101001
  fake_proc 301 mpv mpv film.mkv
  fake_fd 301 4 /home/user/film.mkv 0100000
  rec_detect
  [ "$rec_app" = '' ]
}

@test "listener reports elapsed recording time and resets after recording stops" {
  export ISLAND_REC_INTERVAL=0.05
  mkfifo "$BATS_TEST_TMPDIR/output"
  exec {output_fd}<> "$BATS_TEST_TMPDIR/output"
  "$SCRIPTS/rec" > "$BATS_TEST_TMPDIR/output" 2> "$BATS_TEST_TMPDIR/stderr" &
  listener_pid=$!
  IFS= read -r -t 2 -u "$output_fd" event
  [ "$event" = "$IDLE" ]
  ! IFS= read -r -t 0.3 -u "$output_fd" event
  fake_proc 400 ffmpeg ffmpeg -f x11grab -i :0 out.mp4
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = '{"active":true,"app":"ffmpeg","time":"0:00"}' ]
  IFS= read -r -t 1.5 -u "$output_fd" event
  [ "$event" = '{"active":true,"app":"ffmpeg","time":"0:01"}' ]
  rm -r "${ISLAND_PROC:?}/400"
  IFS= read -r -t 1.5 -u "$output_fd" event
  [ "$event" = "$IDLE" ]
  ! IFS= read -r -t 0.3 -u "$output_fd" event
  fake_obs 401
  fake_proc 402 obs-ffmpeg-mux /usr/bin/obs-ffmpeg-mux
  fake_fd 402 12 /home/user/Videos/rekaman.mkv 0101001
  IFS= read -r -t 1 -u "$output_fd" event
  [ "$event" = '{"active":true,"app":"OBS","time":"0:00"}' ]
}
