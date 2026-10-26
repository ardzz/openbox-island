# Konfigurasi

Detail pemasangan di luar instalasi cepat: dependensi, menjalankan/menghentikan, picom, palet, player, bridge YouTube Music untuk Edge, pintasan, dunst, lokasi cuaca, dan variabel lingkungan.

[README](../README.md) · [Fitur](fitur.md) · [Konfigurasi](konfigurasi.md) · [Debug dan tes](debug.md) · [Arsitektur](architecture.md)

## Dependensi

Visualizer memerlukan sesi audio PipeWire aktif dengan layanan kompatibilitas PulseAudio (`pipewire-pulse`), serta `busctl` dari systemd (sudah termasuk sistem dasar Arch). Jika dependensi visualizer belum terpasang saat island dimulai, pasang dependensinya lalu jalankan ulang `~/.config/openbox/island.sh` agar listener visualizer aktif.

Dependensi aktivitas: `pactl` (paket `libpulse`) untuk volume/mikrofon, scroll, dan mode Output di tab Musik; `inotify-tools` untuk pengamatan kamera dan folder tangkapan layar; `dbus` (`dbus-monitor`) untuk status Jangan Ganggu; `dunst` (`dunstctl`) dan `xdotool` untuk notifikasi; `light` untuk kecerahan; `upower` untuk baterai; NetworkManager (`nmcli`) untuk Wi-Fi; serta `curl` dan `jq` untuk cuaca dan data JSON. Opsional: ImageMagick untuk warna latar tab Musik dari cover, yaitu `magick` (ImageMagick 7, paket Arch `imagemagick`) atau `convert` (ImageMagick 6, misalnya di Ubuntu); tanpa keduanya tab Musik tetap tanpa warna; `geoclue` untuk lokasi otomatis sebelum fallback alamat IP; `gdbus` (paket `glib2`) dan `bluetoothctl` (paket `bluez-utils`) untuk alert Bluetooth; `tailscale` untuk alert Tailscale; `gtk-launch` (paket `gtk3`) untuk membuka aplikasi dari klik notifikasi saat window-nya belum ada.

## Menjalankan dan menghentikan

Island dijalankan otomatis oleh `openbox/eww.sh` dari openbox-omp setiap bar eww dibuka (termasuk ganti tema). Manual: `~/.config/openbox/island.sh`.

Hentikan hanya daemon island (tanpa mengganggu bar eww): `~/.config/openbox/island.sh stop`. Perintah ini aman diulang saat island sudah berhenti.

Agar beralih ke polybar atau tint2 juga menghentikan island, tambahkan baris berikut di dalam `stop_eww()` pada `~/.config/openbox/themes/launch-bar.sh`:

```bash
[[ -x $HOME/.config/openbox/island.sh ]] && "$HOME/.config/openbox/island.sh" stop
```

## picom

picom tidak boleh menggambar bayangan untuk window eww: tambahkan `"class_g = 'Eww'         || "` ke daftar `match` pada rule `shadow = false` di `~/.config/picom.conf`, karena tanpa itu picom menggambar bayangan persegi di sekitar window island yang transparan (dan bar).

## Palet dan font

Font dan warna teks island mengikuti palet tema bar (`~/.config/eww/_colors.scss`), yang disalin setiap kali `island.sh` dimulai; latar island tetap hitam pekat tanpa border dan aksennya (visualizer, progress, meter HUD) hijau `#3ee6c4`. Tanpa palet bar, island memakai palet default dengan font Inter (paket `inter-font`). Ikon selalu dari Symbols Nerd Font (`ttf-nerd-fonts-symbols`). Island memakai bobot 400, 500, dan 600, angka tabular, dan italic untuk lirik; font bar yang tidak punya bobot atau italic itu jatuh ke bobot terdekat dan miring buatan GTK.

## Player

Island hanya menampilkan YouTube Music. Urutan prioritas ada di `eww/players` (default `ytm_player,ytermusic,edge`): nama player MPRIS dipisah koma, diteruskan ke `playerctl --player`. Hanya tiga player ini yang diterima:

- `ytm_player` ([ytm-player](https://ytm-player.com)) dan `ytermusic`: selalu dianggap YouTube Music.
- `edge` (Microsoft Edge): hanya tampil bila [bridge YouTube Music](#bridge-youtube-music-untuk-edge) membuktikan bahwa lagu yang diputar berasal dari tab `music.youtube.com`. Tanpa bridge, Edge tidak pernah tampil.

Nama player lain di berkas ini, termasuk wildcard `%any`, tidak lagi menampilkan player tersebut: rekamannya dibuang, sehingga player itu tidak pernah muncul di island. Lihat nama player: `playerctl -l`. Setelah mengubah, jalankan ulang `~/.config/openbox/island.sh`.

## Bridge YouTube Music untuk Edge

MPRIS Edge tidak membawa URL tab, sehingga island tidak dapat membedakan YouTube Music dari YouTube biasa atau media web lain. Ekstensi `browser/ytm-bridge` (Manifest V3, hanya berjalan di `https://music.youtube.com/*`, izin `nativeMessaging`) mengirim judul, artis, album, video ID, dan status putar dari tab YouTube Music ke native host `eww/scripts/lib/ytm/bridge-host.sh`. Bridge hanya membaca metadata; ia tidak mengklik, memutar, atau mengendalikan pemutaran.

Pemasangan (memerlukan Bash, `jq`, dan GNU coreutils):

1. Buka `edge://extensions`, aktifkan Mode pengembang, lalu pilih **Load unpacked** (Muat yang dibongkar) dan pilih folder `browser/ytm-bridge` dari repositori ini.
2. Salin ID ekstensi yang tampil di kartu ekstensi.
3. Jalankan installer dengan ID tersebut:

   ```bash
   browser/ytm-bridge/install.sh ID_EKSTENSI
   ```

   ID juga dapat diberikan lewat `YTM_BRIDGE_EXT_ID`. Tanpa ID, installer hanya mencetak langkah 1–2 lalu keluar dengan status 1.
4. Muat ulang ekstensi, lalu buka atau muat ulang tab `https://music.youtube.com/`.

Installer menulis `~/.config/microsoft-edge/NativeMessagingHosts/com.openbox_island.ytm_bridge.json` yang hanya mengizinkan ID ekstensi tersebut. Path host di berkas itu menunjuk ke lokasi repositori saat ini; jalankan installer lagi jika repositori dipindah atau ID ekstensi berubah.

Host menulis status terakhir ke `$XDG_RUNTIME_DIR/eww-island/ytm-browser.json`. Edge dianggap YouTube Music hanya selama status itu berumur paling lama 15 detik dan judulnya sama dengan judul MPRIS Edge setelah normalisasi; aturan lengkapnya ada di [Fitur → Musik](fitur.md#musik).

## Tombol suka YouTube Music

Tombol suka/tidak suka YouTube Music memerlukan [ytm-player](https://ytm-player.com) (CLI `ytm`, nama MPRIS `ytm_player`) yang sudah login, serta paket Python `ytmusicapi` untuk membaca status suka. Login dibaca dari `~/.config/ytm-player/auth.json` (ubah dengan `OB_YTM_AUTH`). Tanpa keduanya tombol tidak tampil.

Perilaku tombol dan baris lagu berikutnya: [Fitur → Musik](fitur.md#musik).

## Pintasan

Tombol tab Pintasan dibaca dari `eww/shortcuts`, satu baris per tombol `IKON | LABEL | PERINTAH` (opsional `| dnd`). Format lengkap dan daftar bawaan: [Fitur → Pintasan](fitur.md#pintasan).

## Integrasi dunst

Jika `dunstctl` tersedia, setelah window island berhasil dibuka launcher memasang drop-in `${XDG_CONFIG_HOME:-$HOME/.config}/dunst/dunstrc.d/50-eww-island-osd.conf` lalu memuat ulang dunst. Drop-in ini menyembunyikan semua popup notifikasi (tetap tersimpan di riwayat dunst) dan menyerahkan setiap notifikasi ke `scripts/notify-hook` lewat opsi `script` dunst; hanya kegagalan launcher (aplikasi `eww-island`) yang tetap tampil sebagai popup. Hook memerlukan `always_run_script = true` di dunst (nilai default). Notifikasi bertag `obvolume` dan `obbacklight` disembunyikan termasuk dari riwayat agar OSD tidak muncul dua kali. `island.sh stop` menghapus drop-in tersebut dan memuat ulang dunst; restart juga menghapus aturan lama sebelum memasang ulang. Kegagalan pemasangan atau reload dunst tidak menggagalkan launcher.

## Lokasi cuaca

Urutan lokasi: berkas `eww/weather-location` (diabaikan git) → GeoClue → perkiraan alamat IP. Isi berkas tersebut dengan lokasi pilihan untuk mengganti lokasi otomatis. Kota dan wilayah berasal dari reverse geocoding OpenStreetMap Nominatim (Data © OpenStreetMap contributors, ODbL), dengan cache 30 hari; hanya kunci cache yang dibulatkan ke area sekitar 1 km.

GeoClue opsional: pasang dengan `sudo pacman -S geoclue`, lalu tambahkan ke `/etc/geoclue/geoclue.conf`:

```ini
[geoclue-where-am-i]
allowed=true
system=false
users=
```

Jalankan demo agent saat login, misalnya tambahkan `/usr/lib/geoclue-2.0/demos/agent &` ke `~/.config/openbox/autostart`. Laptop tanpa GPS dapat menggunakan penentuan posisi Wi-Fi melalui layanan lokasi yang dikonfigurasi di GeoClue.

**Privasi:** wttr.in menerima alamat IP dan lokasi yang diminta, termasuk koordinat penuh dari GeoClue jika digunakan. Nominatim menerima koordinat penuh dari GeoClue atau hasil lokasi wttr.in, bukan koordinat yang dibulatkan untuk kunci cache. Penentuan posisi Wi-Fi GeoClue mengirim data access point Wi-Fi di sekitar ke layanan lokasinya.

## Variabel lingkungan

Diset saat menjalankan `~/.config/openbox/island.sh`; daemon dan listener mewarisinya. Setiap variabel dicek terhadap kode di kolom "Dibaca oleh".

| Variabel | Bawaan | Fungsi | Dibaca oleh | Lihat |
| --- | --- | --- | --- | --- |
| `ISLAND_VIZ_FPS` | refresh rate monitor (1–240, 60 bila tidak terbaca) | FPS visualizer, bilangan bulat 1–240 | `eww/scripts/lib/viz/cava.sh` | [pill-dan-kartu](fitur.md#pill-dan-kartu) |
| `ISLAND_MEDIA_GRACE` | `1.5` | Detik tanpa lagu sebelum musik dianggap berhenti; `0` = langsung | `eww/scripts/lib/media/transition.sh` | [musik](fitur.md#musik) |
| `ISLAND_FULLSCREEN_HIDE` | `1` | `0` mematikan penyembunyian island saat layar penuh | `openbox/island.sh`, `eww/scripts/fullscreen` | [layar-penuh](fitur.md#layar-penuh) |
| `ISLAND_NOTIFY_SECONDS` | `4` | Lama tiap notifikasi tampil di pill (detik) | `eww/scripts/notify` | [notifikasi](fitur.md#notifikasi) |
| `ISLAND_SCREENSHOT_DIR` | `$(xdg-user-dir PICTURES)/Screenshots` | Folder tangkapan layar yang dipantau | `eww/scripts/lib/alert/screenshot.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_TEMP_CPU` | `95` | Batas alert suhu CPU (°C) | `eww/scripts/lib/alert/temperature.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_TEMP_GPU` | `87` | Batas alert suhu GPU (°C) | `eww/scripts/lib/alert/temperature.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_TEMP_INTERVAL` | `5` | Interval baca suhu hwmon (detik) | `eww/scripts/lib/alert/temperature.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_POWER_INTERVAL` | `2` | Interval baca profil daya ACPI (detik) | `eww/scripts/lib/alert/power.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_CONSERVATION` | `/sys/bus/platform/devices/VPC2004:*/conservation_mode` | Berkas mode konservasi baterai Lenovo | `eww/scripts/lib/alert/conservation.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_CONSERVATION_INTERVAL` | `5` | Interval baca mode konservasi (detik) | `eww/scripts/lib/alert/conservation.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_VPN_INTERVAL` | `10` | Interval pemeriksaan VPN/Tailscale (detik) | `eww/scripts/lib/alert/vpn.sh` | [aktivitas](fitur.md#aktivitas) |
| `ISLAND_REC_INTERVAL` | `2` | Interval pemeriksaan `/proc` untuk perekaman layar saat tidak merekam (detik) | `eww/scripts/rec` | [indikator](fitur.md#indikator) |
| `ISLAND_DEADLINE_TIME` | `17:00` | Waktu bawaan penanggal deadline (dan tenggat template prep `Nh`) | `eww/scripts/lib/todo/picker.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_DEADLINE_EVE` | `09:00` | Jam pengingat H-1; nilai kosong menonaktifkannya | `eww/scripts/lib/todo/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_DEADLINE_DAY` | `09:00` | Jam pengingat hari H; nilai kosong menonaktifkannya | `eww/scripts/lib/todo/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_DEADLINE_INTERVAL` | `30` | Interval pemeriksaan pengingat deadline (detik) | `eww/scripts/lib/alert/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_TODO_TICK` | `60` | Interval pembaruan label dan warna deadline pada daftar tugas (detik) | `eww/scripts/todo` | [deadline](fitur.md#deadline) |
| `ISLAND_CALENDARS` | `~/.config/openbox-island/calendars` | Berkas akun kalender iCal (mengikuti `XDG_CONFIG_HOME` bila diset); `google-client.json` dan `google-tokens.json` untuk akun Google Calendar API berada di folder yang sama dengan berkas ini | `eww/scripts/agenda_pkg/config.py`, `eww/scripts/lib/alert/meeting.sh` | [kalender](fitur.md#kalender) |
| `ISLAND_CAL_INTERVAL` | `300` | Interval pengambilan ulang feed kalender (detik) | `eww/scripts/agenda_pkg/main.py` | [kalender](fitur.md#kalender) |
| `ISLAND_CAL_DAYS` | `30` | Jumlah hari ke depan setelah hari ini yang ditampilkan agenda (maksimum 366; nilai bukan angka atau di bawah 1 memakai 30) | `eww/scripts/agenda_pkg/main.py` | [kalender](fitur.md#kalender) |
| `ISLAND_MEETING_BEFORE` | `10` | Menit sebelum rapat untuk pengingat; nilai kosong menonaktifkannya | `eww/scripts/lib/alert/meeting.sh` | [kalender](fitur.md#kalender) |
| `ISLAND_MEETING_AUTO` | `10` | Lama kartu Kalender terbuka saat pengingat rapat (detik) | `eww/scripts/lib/alert/meeting.sh` | [kalender](fitur.md#kalender) |
| `ISLAND_KALENDER_TICK` | `2` | Interval pembacaan data lokal untuk tab Kalender (detik) | `eww/scripts/kalender` | [kalender](fitur.md#kalender) |
| `ISLAND_PREP` | `~/.config/openbox-island/prep` (mengikuti `XDG_CONFIG_HOME` bila diset) | Berkas template persiapan meeting | `eww/scripts/lib/prep/template.sh` | [persiapan-meeting](fitur.md#persiapan-meeting) |
| `ISLAND_PREP_AHEAD` | `24` | Jam ke depan untuk membuat item prep; nilai kosong menonaktifkannya | `eww/scripts/lib/prep/sync.sh` | [persiapan-meeting](fitur.md#persiapan-meeting) |
| `ISLAND_PREP_BEFORE` | `2j` | Waktu bawaan sebelum meeting bila `SEBELUM` template kosong (`Nm`, `Nj`, atau `Nh`) | `eww/scripts/lib/prep/template.sh` | [persiapan-meeting](fitur.md#persiapan-meeting) |
| `ISLAND_PREP_INTERVAL` | `60` | Interval sumber alert prep membuat item persiapan (detik) | `eww/scripts/lib/alert/prep.sh` | [persiapan-meeting](fitur.md#persiapan-meeting) |
| `ISLAND_UPCOMING_TICK` | `5` | Detik antar pembacaan ulang agenda dan Tugas untuk pill kiri | `eww/scripts/upcoming` | [pill-kiri](fitur.md#pill-kiri) |
| `ISLAND_BRIDGE_MAX_AGE_MS` | `15000` | Umur maksimum status bridge YouTube Music (milidetik) sebelum Edge tidak lagi dianggap YouTube Music | `eww/scripts/lib/media/gate.sh` | [musik](fitur.md#musik) |
| `ISLAND_BRIDGE_SKEW_MS` | `5000` | Toleransi (milidetik) saat judul MPRIS Edge dan judul bridge sempat berbeda, dihitung dari kecocokan terakhir | `eww/scripts/lib/media/gate.sh` | [musik](fitur.md#musik) |
| `OB_YTM_AUTH` | `~/.config/ytm-player/auth.json` | Login ytm-player untuk status tombol suka (lirik YouTube Music tetap memakai `${XDG_CONFIG_HOME:-$HOME/.config}/ytm-player/auth.json`) | `eww/scripts/ytm_like.py` | [tombol-suka-youtube-music](#tombol-suka-youtube-music) |
