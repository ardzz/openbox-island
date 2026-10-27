# Arsitektur openbox-island

Panduan untuk mengubah atau menambah fitur. Nama fungsi, variabel, dan path ditulis persis seperti di kode.

## 1. Ringkasan

Island adalah konfigurasi eww terpisah (`~/.config/eww-island`) dengan tiga jendela di monitor 0: dua menempel di tepi atas tengah dan satu di pojok kiri atas:

| Jendela | File | Ukuran | Isi |
|---|---|---|---|
| `island` | `eww/yuck/windows/island.yuck` | 508×44 | pill ringkas: `stack` berisi `pill-idle`, `pill-media`, `pill-alert`, `pill-notify` |
| `island-expanded` | `eww/yuck/windows/expanded.yuck` | 508×218 | notch membesar dari pill ringkas menjadi kartu bertab (`tab-card`), dengan crossfade 300 ms |
| `island-upcoming` | `eww/yuck/windows/upcoming.yuck` | 640×44 | pill kiri: rapat yang perlu diperhatikan dan deadline Tugas terdekat |

`scripts/island` membuka/menutup `island-expanded` (hover, `auto`, `dismiss`) dan mengatur `island_reveal` serta `island_tab`.

`island_reveal` menggerakkan ukuran dan radius shell notch; kedua telinga 14 px tetap di sisi atas. Shell menjadi anak utama `overlay` yang menentukan ukuran dan latar; stack crossfade ditumpuk di atasnya agar ukuran minimum kartu tidak memaksa notch langsung membesar. Kartu transparan dan isinya terpotong mengikuti alokasi overlay selama transisi. Urutan tetap: reset reveal → pilih tab → buka jendela → reveal; saat menutup, reset reveal → tunggu 300 ms → tutup jendela.

Alur data: **listener → variabel eww → yuck**. Setiap `deflisten` di `eww/yuck/vars.yuck` menjalankan satu skrip yang mencetak satu baris JSON per perubahan; widget membaca variabel itu. Aksi pengguna (`:onclick`, `:onscroll`, `:onhover`) memanggil skrip yang mengubah state lalu memberi tahu listener lewat FIFO (`fifo_signal`) atau langsung `eww update`.

```mermaid
flowchart LR
  L[openbox/island.sh] -->|eww daemon| D[eww daemon]
  L -->|setsid| FS[scripts/fullscreen]
  L -->|dunst-osd.conf drop-in| DU[dunst]
  D -->|deflisten| S["scripts/media, viz, lyrics, alert,<br/>notify, notif, todo, kalender, status, rec,<br/>ytm, outputs, weather, kuota, shortcuts watch, upcoming"]
  S -->|satu baris JSON| D
  D --> W[yuck: island / island-expanded / island-upcoming]
  W -->|onclick / onscroll / onhover| C["scripts/island, tab, todo, kalender,<br/>notif, notify, scroll, shortcuts, outputs"]
  C -->|fifo_signal NAME.fifo| S
  C -->|eww update| D
  DU -->|script| H[scripts/notify-hook]
  H -->|notify.fifo, notif.fifo| S
  FS -->|island hide / show| C
  S -->|monitor sumber meeting| A[scripts/agenda watch]
  A -->|agenda.json setiap 15 detik| K[scripts/kalender]
  K -->|satu baris JSON| D
  E[Edge: browser/ytm-bridge] -->|native messaging| BH[lib/ytm/bridge-host.sh]
  BH -->|ytm-browser.json| S
```

- `openbox/island.sh`: menghentikan daemon lama, menulis `_colors.scss`, menjalankan `eww daemon`, membuka `island` lalu `island-upcoming`, menjalankan `scripts/fullscreen DAEMON_PID`, memasang `eww/dunst-osd.conf` ke `dunstrc.d`. `island.sh stop` menghentikan semuanya.
- `scripts/fullscreen` bukan deflisten: eww menghentikan deflisten yang variabelnya tidak dipakai jendela terbuka, padahal watcher ini justru menutup kedua jendela.
- `scripts/notify-hook` dijalankan dunst untuk tiap notifikasi; ia hanya mengirim baris ke `notify.fifo` dan `@refresh` ke `notif.fifo`.
- `scripts/agenda watch` mengambil feed iCal dan menulis `$ISLAND_STATE/agenda.json` setiap 15 detik; `scripts/kalender` membaca data itu untuk daftar, scroll, dan Join. Produsen berjalan sebagai monitor sumber alert `meeting`, bukan deflisten khusus kartu: deflisten yang hanya dipakai kartu berhenti saat kartu ditutup, padahal pengingat harus tetap berjalan.
- `scripts/upcoming` (deflisten pill kiri) membaca `$ISLAND_STATE/agenda.json` dan berkas Tugas yang sama setiap `ISLAND_UPCOMING_TICK` detik, lalu mencetak satu baris JSON hanya bila isi pill berubah.
- Persiapan meeting: sumber alert `prep` (`lib/alert/prep.sh`, terdaftar terakhir di `ALERT_SOURCES`) menjalankan `prep_sync` (`lib/prep/sync.sh`) setiap `ISLAND_PREP_INTERVAL` detik. Ia membaca `$ISLAND_STATE/agenda.json` yang `ok == true`, mencocokkan judul dengan template `lib/prep/template.sh` dari `PREP_FILE`, dan untuk occurrence yang belum ada di ledger `${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/prep-made` (baris `ID START`, di bawah lock `prep-made.lock`) menambahkan item Tugas lewat `todo_change` dengan field `prep: <row id>`, `due = start − SEBELUM`, dan `reminded` dari `deadline_passed_keys`; ledger lalu ditulis ulang (baris lebih dari 7 hari dibuang). `scripts/prep sync` menjalankan satu sinkronisasi, `scripts/prep edit ID` memanggil rofi lalu `prep_save` dan `prep_sync`. Display menghitung `prep`/`prep_done` dari item Tugas yang `prep == row.id`: `scripts/kalender` dan `scripts/upcoming` menambahkannya ke JSON baris/meeting, dan `lib/alert/meeting.sh` menambahkan ` · Prep N/M belum selesai` ke isi pengingat selama item row itu belum semua selesai.
- State runtime ada di `$ISLAND_STATE` (`$XDG_RUNTIME_DIR/eww-island`): FIFO `NAME.fifo`, lock, cache.

## 2. Struktur folder

```
openbox/island.sh          launcher: daemon, jendela island, fullscreen watcher, drop-in dunst
eww/eww.yuck               hanya include, urutan: vars → widgets → pill → tabs/<id> → tabs.yuck → windows
eww/eww.scss               hanya @import partial scss/_*.scss
eww/yuck/vars.yuck         semua deflisten/defvar/defpoll (satu baris per deflisten)
eww/yuck/widgets/          widget bersama: cover, skeleton, equalizer, indicators, thumb, tab, list-page
eww/yuck/pill/             halaman pill ringkas: idle, media, alert, notify
eww/yuck/tabs/<id>.yuck    satu halaman tab: page-<id>
eww/yuck/tabs/picker.yuck  penanggal deadline (deadline-picker) di tab Tugas, menggantikan daftar selama terbuka
eww/yuck/tabs.yuck         tab-header (chip) dan tab-card (halaman), urutan sama dengan lib/tabs
eww/yuck/windows/          defwindow island dan island-expanded
eww/scss/_*.scss           gaya per area (lihat peta di §4.5)
eww/scripts/<nama>         entry point: deflisten atau perintah dari yuck
eww/scripts/lib/*.sh       framework bersama (core, store, paged, listener, monitor)
eww/scripts/lib/<area>/    modul per area: alert, status, notify, tabs, viz, weather, media, ytm
eww/scripts/lib/todo/      modul Tugas: deadline.sh (epoch/pengingat), picker.sh (state penanggal + JSON `picker`)
eww/scripts/lyrics         entry Python; logika di eww/scripts/lyrics_pkg/ (sources/: lrclib, netease, ytmusic)
eww/scripts/outputs        sink audio untuk mode Output tab Musik: `watch` (deflisten), `set NAME`, `set-token ID`
eww/scripts/kuota          deflisten tab Kuota: `omp usage` → JSON `kuota`, cache $ISLAND_STATE/kuota.json
eww/scripts/lib/media/     gate.sh (bukti YouTube Music), color.sh (warna cover), record.sh (JSON media), art.sh, transition.sh
eww/scripts/lib/ytm/bridge-host.sh native host Edge: pesan ekstensi → $ISLAND_STATE/ytm-browser.json
browser/ytm-bridge/        ekstensi MV3 Edge (hanya music.youtube.com) + install.sh pendaftar native host
eww/scripts/agenda_pkg/    produsen kalender: config, fetch/cache iCal, Google Calendar API (google.py, login.py), recurring events, render JSON
eww/scripts/prep           CLI prep: `sync` satu sinkronisasi, `edit ID` lewat rofi
eww/rofi/island.rasi       tema rofi untuk form teks Tugas dan prep; lib/rofi.sh (`island_rofi`) memakainya dengan palet bar
eww/scripts/lib/prep/      template.sh (format template) dan sync.sh (membuat item Tugas)
eww/scripts/lib/alert/prep.sh sumber alert `prep` (interval `ISLAND_PREP_INTERVAL`)
eww/{players,shortcuts}    konfigurasi pengguna; cava.conf, dunst-osd.conf, _colors.scss
tools/check                gerbang ukuran file, shellcheck, py_compile
tools/preview              render satu jendela dari sampel ke PNG; sampel di tools/samples/*.vars
tools/showcase             semua sampel ke docs/assets/screenshots/*.png plus demo.gif (ffmpeg x11grab)
tools/lib/preview.sh       salinan config beku + daemon privat, dipakai preview dan showcase
tests/<area>/              tes bats per area (common.bash bersama); tests/lib/ untuk framework; tests/lyrics/ Python
```

## 3. Framework `eww/scripts/lib/`

Semua file di-`source`, tidak dieksekusi. `core.sh` selalu pertama; sisanya "source after core.sh".

### 3.1 `core.sh`

| Nama | Arti |
|---|---|
| `ISLAND_STATE`, `ISLAND_CFG` | dir runtime; dir config eww tempat file ini berada |
| `island_eww ARGS...` | `eww --config "$ISLAND_CFG"` tanpa mewariskan fd 9 (lock) |
| `require TOOL...` | return 127 dan isi `MISSING_DEP` dengan tool pertama yang hilang |
| `run_forever FN [ARGS...]` | ulangi FN selamanya; rc 127 → log sekali, tunggu `OB_RETRY_MISSING` (5 s); lainnya → `OB_RETRY_RECONNECT` (1 s) |
| `emit_dedup` | salin stdin ke stdout, buang baris yang sama dengan sebelumnya |
| `poll_sleep SECONDS` | sleep tanpa fork (read dengan timeout pada pipe kosong) |
| `seconds_us SECONDS` | detik desimal → mikrodetik integer |
| `fifo_signal NAME LINE` | tulis LINE ke `$ISLAND_STATE/NAME.fifo` bila ada; tidak pernah blok |
| `notify_signal LINE`, `notif_signal LINE` | `fifo_signal notify`/`notif` |
| `fmt_time SECONDS` | `m:ss`, atau `h:mm:ss` mulai satu jam |

```bash
main() { run_forever stream | emit_dedup; }   # pola scripts/media dan scripts/weather
```

### 3.2 `store.sh`: file JSON terkunci dan diganti atomik

| Nama | Arti |
|---|---|
| `STORE_VALID_JQ` | opsional; ekspresi jq yang harus menghasilkan tepat `true`, selain itu file dianggap korup |
| `store_valid FILE` | cetak JSON FILE (compact) bila berisi tepat satu nilai valid |
| `store_read FILE DEFAULT_JSON` | isi FILE, atau DEFAULT_JSON bila hilang/korup; tanpa lock |
| `store_update FILE DEFAULT_JSON JQ_FILTER [JQ ARGS...]` | flock `FILE.lock`, terapkan filter, ganti lewat rename. File korup disimpan sebagai `FILE.corrupt`. Gagal tanpa menyimpan bila filter error atau menghasilkan `null`/`false`/bukan satu nilai |

```bash
STORE_VALID_JQ='type == "object" and (.items | type) == "array"'
store_update "$FILE" "$EMPTY" '.items += [{id: $id}]' --argjson id 3 && fifo_signal todo '@refresh'
doc=$(store_read "$FILE" "$EMPTY")
```

### 3.3 `paged.sh`: jendela ROWS item

- `PAGED_JQ`: filter jq dengan variabel `$offset` dan `$rows`; hasil `{rows, more, offset}`, offset di-clamp ke `[0, max(0, n - ROWS)]`, `more` = jumlah item setelah jendela. Disisipkan ke filter render yang lebih besar (`scripts/todo`, `scripts/notif`).
- `paged ITEMS_JSON OFFSET ROWS`: pembungkus jq untuk satu daftar.

```bash
RENDER_JQ='(.items | '"$PAGED_JQ"') as $page | {rows: $page.rows, more: $page.more, offset: $page.offset}'
jq -c --argjson offset "$offset" --argjson rows "$ROWS" "$RENDER_JQ" <<< "$doc"
```

### 3.4 `listener.sh`: loop deflisten berbasis FIFO

`listen NAME RENDER_FN HANDLE_FN` membuat `$ISLAND_STATE/NAME.fifo`, mencetak output RENDER_FN saat mulai dan setiap kali berubah, lalu tidak pernah kembali.

- Tiap baris FIFO → `HANDLE_FN LINE`. Baris dalam `LISTEN_SETTLE` detik (bawaan 0.15) setelah baris pertama dirender sekali (settle). `LISTEN_SETTLE=0` = render setiap baris.
- `listen_tick`: detik tanpa input sebelum HANDLE_FN menerima `@tick`; 0 = tidak pernah. Dibaca ulang tiap iterasi, jadi handler boleh mengubahnya. Pola muat awal: `listen_tick=0.000001`, lalu handler menyetel `listen_tick=0`, sehingga muatan pertama terjadi setelah FIFO ada dan tidak ada `@refresh` yang hilang.
- `listen_render` mencetak hanya bila RENDER_FN sukses dan output berbeda dari sebelumnya.
- **Render berjalan di subshell** (`out=$("$render_fn")`): assignment di RENDER_FN hilang. Ubah state di HANDLE_FN; RENDER_FN hanya mencetak (contoh `notif_render` mencetak `$view` yang dihitung `update`).
- **Shadowing**: handler berjalan di dalam `listen`, jadi local milik `listen` (`render_fn`, `handle_fn`, `line`, `last`, `settle_us`, `deadline`, `active`, `wake`, `tick_seen`, `tick_us`, `remaining`, `timeout`) menutupi variabel pemanggil bernama sama. Karena itu `scripts/notif` memakai `refresh_delay_us`/`tick_every_us`.

```bash
todo_render() { jq -c --argjson offset "$offset" --argjson rows "$ROWS" "$RENDER_JQ" <<< "$doc"; }
todo_handle() { case $1 in '@refresh'|'@tick') load ;; '@scroll 1') scroll 1 ;; esac; listen_tick=0; }
listen_tick=0.000001
LISTEN_SETTLE=0 listen todo todo_render todo_handle
```

### 3.5 `monitor.sh`: monitor event dan worker

| Nama | Arti |
|---|---|
| `monitor_run HANDLER CMD...` | jalankan CMD, kirim tiap baris ke HANDLER sampai CMD selesai |
| `monitor_start` | opsional, nama fungsi yang dipanggil setelah CMD berjalan, sebelum baris pertama: tempat snapshot agar perubahan di antaranya tidak terlewat |
| `monitor_pid` | PID CMD yang berjalan, kosong di luar run; matikan dari trap EXIT worker |
| `workers_start FN...` | jalankan tiap FN di background dengan stdout pemanggil; PID di `worker_pids` |
| `workers_stop` | TERM lalu wait setiap worker |

```bash
monitor_start=dnd_snapshot run_forever monitor_run dnd_event dbus-monitor --session "${DND_MATCH[@]}"
workers_start audio_worker camera_worker >&"$events"; trap workers_stop EXIT
```

## 4. Kontrak area

### 4.1 Sumber alert (`scripts/alert`, `lib/alert/`)

`ALERT_SOURCES` di `scripts/alert` = urutan start worker; tiap NAME punya `lib/alert/NAME.sh`. `source_worker` (`lib/alert/worker.sh`) menjalankan kontraknya:

| Fungsi | Wajib | Arti |
|---|---|---|
| `NAME_init` | tidak | discovery; non-zero menonaktifkan sumber |
| `NAME_snapshot` | ya | sampel state, cetak `alert_json` bila berubah; sampel pertama baseline senyap |
| `NAME_monitor` + `NAME_event LINE` | salah satu | cetak perintah monitor (tiap kata diakhiri NUL) + tangani satu baris |
| `NAME_interval` | salah satu | cetak periode polling (detik) |

Helper: `alert_skip REASON` (catat di stderr lalu gagal), `alert_need TOOL...`, `alert_json KIND ICON TEXT VALUE LEVEL [IMAGE_PATH]`, `level_icon LEVEL LOW MID HIGH` (`lib/alert/common.sh`). Kind `volume|mic|brightness|capslock` bertahan `ISLAND_HUD_SECONDS` (1.5), lainnya `ISLAND_ALERT_SECONDS` (3). Pill memberi kelas `alert-${alert.kind}`.

### 4.2 Sumber status (`scripts/status`, `lib/status/`)

`mic`, `camera`, `dnd`, `headphone`. Tiap sumber mencetak `{"source":...,"active":...,"apps":...}` lewat `<src>_snapshot`, `<src>_event LINE`, `<src>_idle` (dipakai bila tool hilang). Worker dibuat dengan `source_worker SOURCE TOOL... -- CMD...` (`audio_worker`, `camera_worker`, `dnd_worker`, `bluez_worker`); `main` menggabungkan dan baru mencetak setelah keempat sumber (mic, camera, dnd, headphone) melapor.

### 4.3 Registry tab

- Skrip: `eww/scripts/lib/tabs/NN-<id>.sh` mendefinisikan `tab_<id>_available` (sukses = tab ditawarkan). Urutan header = urutan numerik NN. `scripts/tab` (`resolve`, `select`, `next`/`prev`/`up`/`down`) membacanya ke `TABS`.
- UI: `eww/yuck/tabs/<id>.yuck` berisi `page-<id>`; di `eww/yuck/tabs.yuck` satu `tab-chip` di `tab-header` dan satu `tab-page` di `tab-card`; satu `include` di `eww/eww.yuck`.

| Tab | Registry | Tersedia bila |
|---|---|---|
| `musik` | `10-musik.sh` | `media.json` berstatus playing/paused/loading |
| `cuaca` | `20-cuaca.sh` | `weather.ok` |
| `notif` | `30-notif.sh` | riwayat tidak kosong |
| `tugas` | `40-tugas.sh` | `todo.fifo` ada, atau daftar tersimpan punya tugas terbuka |
| `pintasan` | `50-pintasan.sh` | `scripts/shortcuts list` punya tombol |
| `kuota` | `60-kuota.sh` | `$ISLAND_STATE/kuota.json` ada dan `.ok == true` |

### 4.4 Widget bersama (`eww/yuck/widgets/`)

| Widget | Parameter | Pakai untuk |
|---|---|---|
| `list-page` | `onscroll more`; child 0 = baris, child 1 = aksi footer | daftar berhalaman (notif, tugas) |
| `thumb` | `kind image icon` | gambar atau ikon; kelas `KIND-thumb`/`KIND-icon` |
| `tab-chip` / `tab-page` | `id icon name count dot available` / `id` | header (ikon; tab aktif + nama + badge `count` bila > 0; `dot` = titik baru di ikon) dan isi tab (tinggi minimum 164px) |
| `skeleton` | `class width` | placeholder teks yang sedang dimuat |
| `cover` | `size` | cover art `media.art` |
| `equalizer`, `indicators` | – | bar `viz`; titik rec/mic/kamera/DND |

### 4.5 Peta SCSS (`eww/scss/`)

| Partial | Isi |
|---|---|
| `_tokens` | `$island-bg`, `$island-accent`, `$island-fill`, `$island-track`, `$island-accent-soft`, `$red`, `$muted`, `$ear`, `$inset` |
| `_base`, `_pill` | dasar; notch, ear, ukuran halaman pill, indikator |
| `_alert`, `_notify`, `_weather`, `_music` | per area (pill dan tab) |
| `_components` | cover, skeleton, footer `list-more`/`list-action` |
| `_card`, `_notif`, `_todo`, `_picker`, `_shortcuts` | kartu expanded dan tab-tabnya; `_picker` = penanggal deadline di tab Tugas |

Partial baru: buat `eww/scss/_<area>.scss`, tambah `@import "scss/<area>";` di `eww/eww.scss`.

### 4.6 Musik: gate YouTube Music, bridge, lirik, output

**Gate player.** `scripts/media` meneruskan isi `eww/players` (default `ytm_player,ytermusic,edge`) ke `playerctl --player ... --follow metadata`. Setiap rekaman melewati `gate_record` (`lib/media/gate.sh`) di shell pemanggil agar `GATE_LAST_MATCH_MS` bertahan antar-rekaman. `gate_player_ok PLAYER TITLE`:

- `ytm_player`, `ytermusic` (dan instance `NAME.*`) selalu lolos; nama selain `edge`/`edge.*` selalu ditolak.
- `edge` lolos bila `$ISLAND_STATE/ytm-browser.json` punya `ts` bilangan bulat dengan `now - ts <= ISLAND_BRIDGE_MAX_AGE_MS` (15000) dan `norm_title` judul bridge sama dengan `norm_title` judul MPRIS. `norm_title` mengubah ke huruf kecil, hanya menyimpan karakter `[[:alnum:]]`, dan merapatkan spasi.
- Judul tidak cocok masih lolos selama `now - GATE_LAST_MATCH_MS <= ISLAND_BRIDGE_SKEW_MS` (5000) dan kedua judul tidak kosong (selisih waktu ganti lagu antara MPRIS dan bridge).
- Setiap kelolosan Edge menyetel `GATE_DEADLINE_MS` (kedaluwarsa bridge atau batas skew, mana yang lebih dulu). Loop `stream` memakai deadline ini sebagai timeout `read`, lalu memvalidasi ulang rekaman yang sedang tampil tanpa menunggu event playerctl; rekaman yang gagal dikosongkan sehingga `media` menjadi `none`.

**Bridge Edge.** `browser/ytm-bridge` (MV3, izin `nativeMessaging`, content script hanya `https://music.youtube.com/*`) membaca `navigator.mediaSession` setiap detik dan mengirim `{title, artist, album, video_id, playing, ts}` saat berubah, atau ulang setiap 5 detik. Service worker meneruskannya ke native host `com.openbox_island.ytm_bridge`, yang didaftarkan `browser/ytm-bridge/install.sh ID` di `~/.config/microsoft-edge/NativeMessagingHosts/` dengan `allowed_origins` hanya untuk ID itu. `lib/ytm/bridge-host.sh` membaca frame native messaging (panjang 4 byte little-endian + JSON), menerima tepat satu objek dengan `title` dan `artist` bertipe string serta `ts` opsional bertipe angka, mengganti `ts` dengan waktu terima host (`date +%s%3N`, epoch milidetik), lalu menulis `$ISLAND_STATE/ytm-browser.json` secara atomik (temp + `mv`). Pesan tidak valid diabaikan tanpa mengubah status terakhir. Karena `ts` diset host, jam di halaman tidak memengaruhi umur bridge.

**Warna cover.** `media.color` adalah warna cover `#rrggbb` yang dinormalisasi, atau `""` untuk cover yang tidak tersedia atau didominasi abu-abu serta state none/loading. `lib/media/color.sh` mengambil histogram ImageMagick 12×12, mengelompokkan piksel berwarna ke 12 bucket hue, lalu merata-ratakan klaster tetangga terkuat. Hasil di-cache di `${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/art-color/` dengan kunci SHA-1 isi berkas cover, sehingga path lokal yang berganti-ganti memakai ulang warna tanpa menjalankan ImageMagick lagi. Entri cache ditulis atomik lewat berkas sementara dan rename. Berkas cache kosong adalah hasil sah abu-abu/tanpa warna; entri tidak kosong harus `#rrggbb` huruf kecil, selain itu warna dihitung ulang. Dominasi abu-abu ditentukan dari seluruh bobot berwarna (minimal 25% dari total piksel berbobot kecerahan), terlepas dari klaster hue tetangga mana yang memberi warna. `page-musik` memakai warna ini sebagai `background` halaman tab Musik.

**Lirik.** `scripts/lyrics` mencetak `{text, synced, lines, index, for_player, for_title, for_artist, for_length}`. `lines` = `[{t, text}]` dengan `t` timestamp milidetik untuk lirik tersinkron atau `-1` untuk lirik biasa; `index` = baris aktif (`-1` bila belum ada). Untuk lirik biasa, `index` diperkirakan dari posisi × jumlah baris ÷ durasi. `synced` benar hanya bila baris tersinkron sedang tampil. Field `for_player`, `for_title`, `for_artist`, dan `for_length` adalah `player`, `title`, `artist`, dan `length` mentah dari lagu milik lirik itu (`self.track`, tanpa normalisasi), atau `""` untuk teks dan `0` untuk durasi bila tidak ada lagu aktif. Saat listener mulai dan saat lagu berganti, keluaran pertama dibuat lewat `state.output(None)`, sehingga keempat field langsung menunjuk lagu saat itu. Mode Lirik (`musik-lyrics`) memotong `lines` ke `index-2 … index+3` dengan `jq` karena eww tidak bisa menggulir otomatis. Klik baris menjalankan `playerctl --player=${media.player} position t/1000` hanya bila `t >= 0` dan keempat field identitas cocok dengan media, sehingga lirik lagu sebelumnya yang belum diganti tidak memindahkan posisi lagu baru; baris lain dinonaktifkan.

**Output.** `scripts/outputs` (deflisten `outputs`) mencetak `[{name, id, label, active}]` dari `pactl --format=json list sinks`: `id` = `name` dalam base64, `label` = deskripsi sink yang di-trim (atau `name`), `active` = sink default; diurutkan aktif dulu lalu label. Render ulang terjadi pada event sink/server `pactl subscribe` (`monitor_run`). Klik baris menjalankan `outputs set-token ID`: token harus cocok `^[A-Za-z0-9+/=]+$` dan ter-decode base64, sehingga nama sink tidak pernah diinterpolasi mentah ke perintah shell eww. `set_output NAME` berjalan di subshell dan memegang `flock` pada `$ISLAND_STATE/outputs.lock` selama validasi, `set-default-sink`, pembacaan daftar sink input, dan pemindahan, sehingga klik beruntun diproses satu per satu tanpa saling menyela. Ia gagal tanpa mengubah apa pun bila sink tidak lagi ada; selain itu `pactl set-default-sink`, lalu `pactl move-sink-input` untuk setiap sink input. Satu kegagalan pemindahan membuat status keluar 1, tetapi stream lain tetap dipindah. UI hanya merender enam baris pertama plus `+N lainnya`.

**Mode.** `music_mode` (defvar, `player|lyrics|output`) memilih `musik-player`, `musik-lyrics`, atau `musik-outputs` lewat `revealer :transition "none"`.

### 4.7 Kuota: kolektor `omp usage`

`scripts/kuota` (deflisten `kuota`, `main` = `stream | emit_dedup`) menjalankan `omp usage --json --redact --no-extensions` saat mulai lalu setiap `ISLAND_KUOTA_INTERVAL` detik (bawaan 300; nilai bukan bilangan bulat positif memakai 300), dan menormalkannya dengan satu filter jq menjadi:

```json
{"ok":true,"updated":"HH:MM","note":"","accounts":[{"provider":"Codex","plan":"pro","limits":[{"label":"7 hari","used":34,"reset":"5 hr"}]}]}
```

- `accounts` mengikuti urutan `.reports[]` omp; report yang `provider`-nya ada di daftar koma `ISLAND_KUOTA_SKIP` (bawaan `google-antigravity`, kosong = tidak ada yang dilewati) dibuang. `provider` dipetakan `openai-codex`→`Codex`, `anthropic`→`Claude`, `github-copilot`→`Copilot`, `google-antigravity`→`Antigravity`, selain itu ID apa adanya; `plan` = `.metadata.planType // .metadata.plan // ""`.
- `label`: awalan `Claude ` dibuang, `Hour(s)`→`jam`, `Day(s)`→`hari`, `Premium Requests`→`Permintaan premium`. `used` = `.amount.used` bila `.amount.unit == "percent"` dan bertipe angka, selain itu `-1` (UI: `Tanpa batas`). `reset` dari `.window.resetsAt` (epoch milidetik) relatif terhadap waktu ambil: `Nm`, `Nj` / `Nj Mm`, `N hr`, `segera` bila sudah lewat, `—` bila null.
- `updated` = jam pengambilan (`date +%H:%M`); `ISLAND_NOW` menimpa waktu sekarang untuk tes.
- Berhasil: record ditulis atomik ke `$ISLAND_STATE/kuota.json` (`mktemp` + `mv`) lalu dicetak. Gagal setelah pernah berhasil: record terakhir dicetak ulang (`emit_dedup` membuang duplikatnya), cache tidak disentuh. Gagal sebelum pernah berhasil: `{"ok":false,"updated":"","note":"…","accounts":[]}` dengan `note` `omp tidak ditemukan` (tanpa `omp`) atau `gagal memuat kuota`.

Registry `60-kuota.sh` sengaja memeriksa berkas cache, bukan `island_eww get kuota`: deflisten `kuota` hanya hidup selama kartu terbuka, sedangkan `scripts/tab` perlu jawaban ketersediaan saat kartu belum dibuka. Tab baru yang datanya berasal dari listener kartu dapat memakai pola yang sama: listener menulis cache atomik hanya untuk hasil sah, dan predikat registry membaca cache itu dengan `jq -e`.

## 5. Resep

Nama `jadwal`, `fan`, dan `catatan` di bawah hanya contoh.

### 5.1 Menambah tab baru

1. Registry `eww/scripts/lib/tabs/70-jadwal.sh`:
   ```bash
   #!/usr/bin/env bash
   # Jadwal: the schedule listener has at least one item.
   tab_jadwal_available() { [[ $(island_eww get jadwal 2>/dev/null | jq -r '.total // 0' 2>/dev/null) != 0 ]]; }
   ```
2. Halaman `eww/yuck/tabs/jadwal.yuck`, lalu `(include "./yuck/tabs/jadwal.yuck")` sebelum `tabs.yuck` di `eww/eww.yuck`:
   ```lisp
   (defwidget page-jadwal []
     (list-page :onscroll "${EWW_CONFIG_DIR}/scripts/jadwal scroll {} &"
                :more {jadwal.more > 0 ? "+${jadwal.more} lainnya" : ""}
       (box :orientation "v" :space-evenly false :spacing 0
         (for row in {jadwal.rows} (label :class "jadwal-row" :xalign 0 :text {row.text})))
       (box)))
   ```
3. `eww/yuck/tabs.yuck`, pada posisi yang sama dengan NN:
   ```lisp
   (tab-chip :id "jadwal" :icon "󰃭" :name "Jadwal" :count {jadwal.total} :dot false
             :available {jadwal.total > 0})                                    ; di tab-header
   (tab-page :id "jadwal" (page-jadwal))                                   ; di tab-card
   ```
   Tambah tes di `tests/tab/registry.bats` dan sampel `tools/samples/card-jadwal.vars` (`window=island-expanded`, `tab=jadwal`).

### 5.2 Menambah sumber alert baru

1. `eww/scripts/lib/alert/fan.sh` (polling, pola `conservation.sh`):
   ```bash
   #!/usr/bin/env bash
   # Alert source: fan mode changes (sysfs). Source it; do not execute.
   ICON_FAN=$'\U000F0210'
   fan_init() { [[ -r ${ISLAND_FAN:-/sys/devices/platform/fan/mode} ]] || alert_skip 'mode kipas tidak ditemukan'; }
   fan_interval() { printf '%s' "${ISLAND_FAN_INTERVAL:-5}"; }
   fan_snapshot() {
     local mode=''
     IFS= read -r mode 2>/dev/null < "${ISLAND_FAN:-/sys/devices/platform/fan/mode}" || return 0
     if [[ -n ${fan_state:-} && $mode != "$fan_state" ]]; then alert_json fan "$ICON_FAN" 'Mode kipas' "$mode" -1; fi
     fan_state=$mode
   }
   ```
   Untuk sumber berbasis event, ganti `fan_interval` dengan `fan_monitor() { printf '%s\0' CMD ARG...; }` dan `fan_event()` (pola `bluetooth.sh`).
2. Daftarkan di `ALERT_SOURCES` pada `eww/scripts/alert`: `(... conservation vpn fan)`.
3. Tes `tests/alert/fan.bats` (`load helpers`, panggil `fan_snapshot` berulang, cek JSON); gaya opsional `.alert-fan` di `eww/scss/_alert.scss`.

### 5.3 Menambah listener baru (listen + store/paged)

1. `eww/scripts/catatan` (pola `scripts/todo`):
   ```bash
   #!/usr/bin/env bash
   # catatan: deflisten printing saved notes, one JSON object per line. catatan scroll up|down
   DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$DIR/lib/core.sh"; source "$DIR/lib/store.sh"
   source "$DIR/lib/listener.sh"; source "$DIR/lib/paged.sh"
   FILE="${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/catatan.json" ROWS=4 EMPTY='{"items":[]}'
   RENDER_JQ='(.items | '"$PAGED_JQ"') as $page | {total: (.items | length), rows: $page.rows, more: $page.more}'
   load() { doc=$(store_read "$FILE" "$EMPTY"); total=$(jq '.items | length' <<< "$doc"); }
   # scroll STEP: move the window by STEP, clamped like PAGED_JQ.
   scroll() { local top=$(( total > ROWS ? total - ROWS : 0 )); offset=$((offset + $1)); ((offset >= 0)) || offset=0; ((offset <= top)) || offset=$top; }
   catatan_render() { jq -c --argjson offset "$offset" --argjson rows "$ROWS" "$RENDER_JQ" <<< "$doc"; }
   catatan_handle() {
     case $1 in '@refresh'|'@tick') load ;; '@scroll -1') scroll -1 ;; '@scroll 1') scroll 1 ;; esac
     listen_tick=0
   }
   main() {
     case ${1:-} in scroll) fifo_signal catatan "@scroll $([[ $2 == up ]] && echo -1 || echo 1)"; return ;; esac
     require jq || return 127
     local doc='' total=0 offset=0
     listen_tick=0.000001
     LISTEN_SETTLE=0 listen catatan catatan_render catatan_handle
   }
   if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
   ```
   Penulis memakai `store_update "$FILE" "$EMPTY" FILTER ...` lalu `fifo_signal catatan '@refresh'`.
2. Satu baris di `eww/yuck/vars.yuck` (harus satu baris agar `tools/preview` bisa membekukannya):
   ```lisp
   (deflisten catatan :initial '{"total":0,"rows":[],"more":0}' "scripts/catatan")
   ```
3. Tes `tests/catatan/` (`common.bash` + `.bats`) dan pakai variabel `catatan` di widget/tab.

## 6. Kualitas

- **Ukuran file**: target ≤200 baris, batas keras 300. `tools/check [ROOT]` memeriksa file yang di-track di `eww/ openbox/ tools/ tests/` (`.md` di luar cakupan): >200 `WARN`, >300 `FAIL`, `shellcheck -x -s bash -S warning` untuk bash, `py_compile` untuk Python. Dilewati: `*.conf`, `eww/players`, `eww/shortcuts`, gambar.
- **Tes**: `bats -r tests/`, `python -m unittest discover -s tests -p 'test_*.py'`, lalu `tools/check`. Tes mengikuti area: `tests/<area>/*.bats` dengan `common.bash`, `tests/lib/` untuk framework, `tests/tools/` untuk tools; `tests/helpers.bash` menyediakan `REPO` dan `SCRIPTS`.
- **Preview dan perbandingan piksel**: `tools/preview CONFIG_DIR SAMPLE OUT.png` menyalin config ke `/tmp`, mengganti setiap `deflisten`/`defpoll` dengan `defvar` berisi `:initial`, mematikan animasi, lalu merender jendela 300px di bawah tepi atas pada `DISPLAY` aktif. Sampel `tools/samples/*.vars`: `window=island|island-expanded`, opsional `tab=<id>`, lalu `var=<json>`; `@ASSETS@` = `tools/samples/assets/`. Alur yang disarankan: render baseline sebelum perubahan, render ulang sesudahnya, bandingkan dengan `compare` ImageMagick (yang juga menyediakan `import` yang dipakai preview):
  ```bash
  mkdir -p ~/.cache/island-baseline /tmp/island-new
  for f in tools/samples/*.vars; do tools/preview eww "$f" ~/.cache/island-baseline/"$(basename "$f" .vars)".png; done
  # ...ubah kode, lalu render ulang ke /tmp/island-new dengan loop yang sama...
  compare -metric AE ~/.cache/island-baseline/card-todo.png /tmp/island-new/card-todo.png /tmp/diff.png
  ```
- **Aset README**: `tools/showcase docs/assets` merender setiap sampel ke `docs/assets/screenshots/<nama>.png` (PNG sampel yang sudah tidak ada dihapus), lalu menjalankan satu daemon dengan animasi menyala dan merekam skenario ±12 detik (pill musik, kartu terbuka dan berpindah tab, alert volume, notifikasi) dari wilayah 520×230 di y=300 dengan `ffmpeg -f x11grab` menjadi `docs/assets/demo.gif`. Nilai demo diambil dari sampel (`card-music-ytm`, `card-notif`, `card-todo`, `card-shortcuts-dnd`, `pill-notify`). Latar belakang render diatur `PREVIEW_BACKDROP` (warna atau `linear-gradient(...)` CSS): `tools/preview` memakai `#808080` agar baseline perbandingan piksel tetap sama, `tools/showcase` memakai gradien gelap mirip desktop. Jangan gerakkan mouse selama perekaman; tooltip disembunyikan dan `scripts/island` di salinan diganti no-op agar pointer di atas wilayah itu tidak mengubah gambar.

### Quirk eww 0.5
| Quirk | Akibat di proyek |
|---|---|
| `stack :selected` yang sudah terisi saat jendela dibangun tidak menampilkan halaman | `tools/preview` membuka jendela dulu, baru `eww update` |
| `:visible` tetap tersembunyi di halaman stack yang belum pernah tampil | pakai `revealer :transition "none"` (`thumb`, `tab-chip`, `tab-page`) |
| Geometri jendela statis | `island` 508×44, `island-expanded` 508×218; isi tab harus muat (mis. 4 baris + footer di `notif`) |
| `onscroll` hanya melaporkan scroll vertikal | ganti tab dengan scroll atas/bawah di header (`scripts/tab {}`) |
| Urutan include | pertahankan urutan di `eww/eww.yuck`: vars → widgets → pill → tabs/<id> → `tabs.yuck` → windows |
| `onhover`/`onhoverlost` juga terpicu oleh pointer grab | `scripts/island` membaca posisi pointer sendiri (`hovered`) |
