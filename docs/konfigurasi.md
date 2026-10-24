# Konfigurasi

Detail pemasangan di luar instalasi cepat: dependensi, menjalankan/menghentikan, picom, palet, player, pintasan, dunst, lokasi cuaca, dan variabel lingkungan.

[README](../README.md) · [Fitur](fitur.md) · [Konfigurasi](konfigurasi.md) · [Debug dan tes](debug.md) · [Arsitektur](architecture.md)

## Dependensi

Visualizer memerlukan sesi audio PipeWire aktif dengan layanan kompatibilitas PulseAudio (`pipewire-pulse`), serta `busctl` dari systemd (sudah termasuk sistem dasar Arch). Jika dependensi visualizer belum terpasang saat island dimulai, pasang dependensinya lalu jalankan ulang `~/.config/openbox/island.sh` agar listener visualizer aktif.

Dependensi aktivitas: `pactl` (paket `libpulse`) untuk volume/mikrofon dan scroll; `inotify-tools` untuk pengamatan kamera dan folder tangkapan layar; `dbus` (`dbus-monitor`) untuk status Jangan Ganggu; `dunst` (`dunstctl`) dan `xdotool` untuk notifikasi; `light` untuk kecerahan; `upower` untuk baterai; NetworkManager (`nmcli`) untuk Wi-Fi; serta `curl` dan `jq` untuk cuaca dan data JSON. Opsional: `geoclue` untuk lokasi otomatis sebelum fallback alamat IP; `gdbus` (paket `glib2`) dan `bluetoothctl` (paket `bluez-utils`) untuk alert Bluetooth; `tailscale` untuk alert Tailscale; `gtk-launch` (paket `gtk3`) untuk membuka aplikasi dari klik notifikasi saat window-nya belum ada.

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

Font dan warna teks island mengikuti palet tema bar (`~/.config/eww/_colors.scss`), yang disalin setiap kali `island.sh` dimulai; latar island tetap hitam pekat tanpa border dan aksennya (visualizer, progress, meter HUD) hijau `#3ee6c4`. Tanpa palet bar, island memakai palet default.

## Player

Urutan prioritas ada di `eww/players` (default `ytm_player,ytermusic,edge,%any`; `ytm_player` adalah [ytm-player](https://ytm-player.com)): nama player MPRIS dipisah koma, `%any` = player lain. Lihat nama player: `playerctl -l`. Setelah mengubah, jalankan ulang `~/.config/openbox/island.sh`.

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
| `ISLAND_DEADLINE_TIME` | `17:00` | Waktu deadline untuk tanggal yang diketik tanpa jam | `eww/scripts/lib/todo/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_DEADLINE_EVE` | `09:00` | Jam pengingat H-1; nilai kosong menonaktifkannya | `eww/scripts/lib/todo/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_DEADLINE_DAY` | `09:00` | Jam pengingat hari H; nilai kosong menonaktifkannya | `eww/scripts/lib/todo/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_DEADLINE_INTERVAL` | `30` | Interval pemeriksaan pengingat deadline (detik) | `eww/scripts/lib/alert/deadline.sh` | [deadline](fitur.md#deadline) |
| `ISLAND_TODO_TICK` | `60` | Interval pembaruan label dan warna deadline pada daftar tugas (detik) | `eww/scripts/todo` | [deadline](fitur.md#deadline) |
| `ISLAND_CALENDARS` | `~/.config/openbox-island/calendars` | Berkas akun kalender iCal (mengikuti `XDG_CONFIG_HOME` bila diset) | `eww/scripts/agenda_pkg/config.py`, `eww/scripts/lib/alert/meeting.sh` | [kalender](fitur.md#kalender) |
| `ISLAND_CAL_INTERVAL` | `300` | Interval pengambilan ulang feed kalender (detik) | `eww/scripts/agenda_pkg/main.py` | [kalender](fitur.md#kalender) |
| `ISLAND_MEETING_BEFORE` | `10` | Menit sebelum rapat untuk pengingat; nilai kosong menonaktifkannya | `eww/scripts/lib/alert/meeting.sh` | [kalender](fitur.md#kalender) |
| `ISLAND_MEETING_AUTO` | `10` | Lama kartu Kalender terbuka saat pengingat rapat (detik) | `eww/scripts/lib/alert/meeting.sh` | [kalender](fitur.md#kalender) |
| `ISLAND_KALENDER_TICK` | `2` | Interval pembacaan data lokal untuk tab Kalender (detik) | `eww/scripts/kalender` | [kalender](fitur.md#kalender) |
| `ISLAND_UPCOMING_TICK` | `5` | Detik antar pembacaan ulang agenda dan Tugas untuk pill kiri | `eww/scripts/upcoming` | [pill-kiri](fitur.md#pill-kiri) |
| `OB_YTM_AUTH` | `~/.config/ytm-player/auth.json` | Login ytm-player untuk status tombol suka (lirik YouTube Music tetap memakai `${XDG_CONFIG_HOME:-$HOME/.config}/ytm-player/auth.json`) | `eww/scripts/ytm_like.py` | [tombol-suka-youtube-music](#tombol-suka-youtube-music) |
