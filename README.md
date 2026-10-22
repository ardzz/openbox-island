# openbox-island

Notch ala Dynamic Island untuk Openbox (eww): now playing YouTube Music atau player MPRIS lain (cover, lirik tersinkron, visualizer audio, kontrol), alert volume/kecerahan/baterai/Wi-Fi, indikator mikrofon/kamera/Jangan Ganggu, dan cuaca.

## Pasang

```bash
git clone https://github.com/ardzz/openbox-island.git && cd openbox-island
sudo pacman -S --needed playerctl jq curl xdotool cava pipewire-audio libpulse inotify-tools python dbus light upower networkmanager
ln -s "$PWD/eww" ~/.config/eww-island
ln -s "$PWD/openbox/island.sh" ~/.config/openbox/island.sh
```

Visualizer memerlukan sesi audio PipeWire aktif dengan layanan kompatibilitas PulseAudio (`pipewire-pulse`), serta `busctl` dari systemd (sudah termasuk sistem dasar Arch). Jika dependensi visualizer belum terpasang saat island dimulai, pasang dependensinya lalu jalankan ulang `~/.config/openbox/island.sh` agar listener visualizer aktif.

Island dijalankan otomatis oleh `openbox/eww.sh` dari openbox-omp setiap bar eww dibuka (termasuk ganti tema). Manual: `~/.config/openbox/island.sh`.

Font dan warna teks island mengikuti palet tema bar (`~/.config/eww/_colors.scss`), yang disalin setiap kali `island.sh` dimulai; latar island tetap hitam pekat tanpa border dan aksennya (visualizer, progress, meter HUD) hijau `#3ee6c4`. Tanpa palet bar, island memakai palet default.

Hentikan hanya daemon island (tanpa mengganggu bar eww): `~/.config/openbox/island.sh stop`. Perintah ini aman diulang saat island sudah berhenti.

Agar beralih ke polybar atau tint2 juga menghentikan island, tambahkan baris berikut di dalam `stop_eww()` pada `~/.config/openbox/themes/launch-bar.sh`:

```bash
[[ -x $HOME/.config/openbox/island.sh ]] && "$HOME/.config/openbox/island.sh" stop
```

Window island bersifat override-redirect (`:wm-ignore true`), jadi Openbox tidak mengelolanya dan klik pada bar tidak bisa menaikkan bar menutupi island.

picom tidak boleh menggambar bayangan untuk window eww: tambahkan `"class_g = 'Eww'         || "` ke daftar `match` pada rule `shadow = false` di `~/.config/picom.conf`, karena tanpa itu picom menggambar bayangan persegi di sekitar window island yang transparan (dan bar).

## Player

Urutan prioritas ada di `eww/players` (default `ytermusic,edge,%any`): nama player MPRIS dipisah koma, `%any` = player lain. Lihat nama player: `playerctl -l`. Setelah mengubah, jalankan ulang `~/.config/openbox/island.sh`.

## Perilaku

- Idle: island tetap berupa pill kecil dengan cuaca dan indikator aktivitas; jika tidak ada informasi, pill tetap terlihat kosong. Jam ada di bar. Ada musik: cover + satu baris lirik + enam bar spektrum audio nyata serta indikator aktivitas dalam island 480×36 px. Visualizer diproses pada 20 fps; frame yang tidak berubah tidak dikirim ulang. Bar rata setinggi 4 px saat hening, pause, tidak ada stream yang cocok, atau terjadi error; tidak ada animasi pengganti.
- Hover: membesar menjadi 480×180 px setelah pointer diam di atas island selama 0,3 detik (cover, judul, artis, satu baris lirik, progress, ⏮ ⏯ ⏭). Ganti lagu: membesar 4 detik lalu menciut; selama pointer di atas island, ganti lagu tidak menciutkannya.
- Saat membesar, judul lebih dari 30 karakter dan artis lebih dari 36 karakter bergulir sekitar 5 karakter/detik, dengan jeda 1,2 detik di awal tiap putaran dan pemisah `   ·   `. Teks pendek tetap diam; guliran dimulai ulang saat window dibuka atau lagu berganti, tanpa polling saat menciut.
- Hover dibaca dari posisi pointer (`xdotool`), bukan dari urutan event enter/leave eww: event itu juga muncul saat aplikasi lain meng-grab pointer dan bisa diproses tidak berurutan.
- Visualizer hanya mengambil stream keluaran milik PID player MPRIS aktif atau proses turunannya, bukan mikrofon, monitor audio sistem, atau sumber audio default sebagai fallback. Metadata dan kontrol MPRIS tetap bekerja jika visualizer tidak mendapat audio.
- Audio visualizer hanya lewat memori/FIFO lokal, tidak disimpan atau diunggah. Unduhan cover tetap menggunakan jaringan.
- Lirik tersinkron dari LRCLIB, dengan NetEase Cloud Music sebagai fallback, tampil miring dan rata tengah pada kedua ukuran island. Baris panjang dipotong dengan elipsis, tanpa bergulir atau mengecilkan font; tooltip menampilkan teks lengkap. Posisi MPRIS dibaca setiap 250 ms saat player aktif; listener hanya mengirim perubahan teks/status sinkron, bukan frame berulang. Saat belum ada baris lirik, intro, instrumental, hasil tidak tersedia, atau lookup gagal/timeout tanpa cache positif, judul dan artis asli tampil dengan warna redup.
- LRCLIB tidak memerlukan API key. Pencarian mengirim metadata judul, artis, dan durasi, bukan audio. Cache hasil positif berlaku 30 hari; hasil positif kedaluwarsa masih dipakai jika layanan gagal diakses. Cache negatif berlaku 24 jam hanya jika kedua sumber memastikan tidak ada lirik tersinkron. Error jaringan/timeout tidak disimpan sebagai hasil negatif.

## Aktivitas

Alert menggantikan isi pill sementara, hanya pada tampilan ringkas; tampilan yang sedang membesar tidak berubah. Alert volume, mikrofon, kecerahan, dan Caps Lock bertahan 1,5 detik; alert lain bertahan 3 detik.

| Jenis | Teks |
| --- | --- |
| `volume` | `Volume` atau `Bisu`, dengan persentase volume |
| `mic` | `Mikrofon nyala` atau `Mikrofon mati` |
| `brightness` | `Kecerahan`, dengan persentase |
| `charging` | `Mengisi daya` saat charger dipasang, dengan persentase; ikon berwarna aksen dan berdenyut beberapa kali |
| `battery` | `Charger dicabut` atau `Baterai penuh`, dengan persentase |
| `battery-low` | `Baterai lemah` saat melewati 20% atau `Baterai kritis` saat melewati 10% ketika daya sedang dipakai; ikon dan meter berwarna merah |
| `wifi` | `Wi-Fi tersambung` dengan nama koneksi, atau `Wi-Fi terputus` |
| `bluetooth` | `Bluetooth tersambung` atau `Bluetooth terputus`, dengan nama perangkat (alias) serta persentase baterai saat tersambung jika perangkat melaporkannya; ikon mengikuti jenis perangkat (headphone, gamepad, mouse, keyboard, ponsel) |
| `screenshot` | `Tangkapan layar` dengan nama berkas dan thumbnail gambar sebagai pengganti ikon, saat berkas `.png`/`.jpg`/`.jpeg` baru selesai ditulis atau dipindahkan ke folder tangkapan layar |
| `temperature` | `CPU panas` atau `GPU panas` dengan suhunya, sekali saat suhu mencapai batas (CPU 95 °C, GPU 87 °C; ubah dengan `ISLAND_TEMP_CPU`/`ISLAND_TEMP_GPU`); muncul lagi hanya setelah suhu turun di bawah batas − 5 °C. Ikon berwarna merah |
| `capslock` | `Caps Lock nyala` atau `Caps Lock mati` saat status LED Caps Lock keyboard (`/sys/class/leds/*::capslock`, dibaca setiap 0,25 detik) berubah |

Folder tangkapan layar: `ISLAND_SCREENSHOT_DIR` jika diset, selain itu `Screenshots` di dalam folder Gambar XDG (`xdg-user-dir PICTURES`), atau `~/Pictures/Screenshots`. Folder dibuat jika belum ada.

Suhu dibaca langsung dari hwmon (`/sys/class/hwmon`) setiap 5 detik (`ISLAND_TEMP_INTERVAL`), tanpa `sensors` atau `nvidia-smi` agar GPU diskrit tidak terbangun. Sensor CPU berlabel `CPU Temperature`, `Package id 0`, atau `Tctl` (urutan prioritas); sensor GPU berlabel `GPU Temperature`. Tanpa sensor yang cocok, alert suhu tidak aktif. Saat island dimulai dalam kondisi sudah panas, alert baru muncul setelah suhu turun lalu naik lagi.

Indikator tampil pada pill idle dan media: titik kuning berarti mikrofon dipakai, titik hijau berarti kamera dipakai, dan ikon lonceng dicoret berarti Jangan Ganggu dunst aktif. Tooltip mikrofon dan kamera mencantumkan aplikasi yang memakainya. Deteksi kamera hanya melihat proses milik pengguna yang sama.

Scroll ke atas/bawah di atas island ringkas mengubah volume keluaran default sebesar ±5%. Perubahan ini sekaligus membuka bisu (unmute), dengan batas 0–100%.

Jika `dunstctl` tersedia, setelah window island berhasil dibuka launcher memasang aturan penekan OSD volume/kecerahan ke `${XDG_CONFIG_HOME:-$HOME/.config}/dunst/dunstrc.d/50-eww-island-osd.conf` lalu memuat ulang dunst. Aturan ini hanya menyembunyikan notifikasi bertag `obvolume` dan `obbacklight`, termasuk dari riwayat, agar OSD tidak muncul dua kali. `island.sh stop` menghapus drop-in tersebut dan memuat ulang dunst; restart juga menghapus aturan lama sebelum memasang ulang. Kegagalan pemasangan atau reload dunst tidak menggagalkan launcher.

Cuaca berasal dari wttr.in. Pill idle menampilkan ikon, suhu, dan kota, rata tengah. Hover di atas island idle selama 0,3 detik membuka kartu detail 480×180 px: kondisi cuaca, suhu, kota dan wilayah, waktu matahari terbit/terbenam, suhu terasa, kelembapan, angin, indeks UV, serta prakiraan 3 hari dengan suhu maksimum/minimum dan peluang hujan. Jika cuaca tidak tersedia, hover idle tidak membuka kartu. Cuaca diperbarui setiap 30 menit, dicoba ulang setelah 5 menit jika gagal, dan cache dapat dipakai selama 3 jam.

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

Dependensi aktivitas: `pactl` (paket `libpulse`) untuk volume/mikrofon dan scroll; `inotify-tools` untuk pengamatan kamera dan folder tangkapan layar; `dbus` (`dbus-monitor`) untuk status Jangan Ganggu; `light` untuk kecerahan; `upower` untuk baterai; NetworkManager (`nmcli`) untuk Wi-Fi; serta `curl` dan `jq` untuk cuaca dan data JSON. Opsional: `geoclue` untuk lokasi otomatis sebelum fallback alamat IP; `gdbus` (paket `glib2`) dan `bluetoothctl` (paket `bluez-utils`) untuk alert Bluetooth.

## Fallback lirik NetEase

Listener mencoba NetEase Cloud Music jika LRCLIB tidak menghasilkan lirik tersinkron yang cocok, termasuk saat LRCLIB gagal sementara. Endpoint NetEase ini tidak resmi dan dapat berubah atau berhenti tersedia. Listener mengirim judul dan artis ke server NetEase untuk pencarian, lalu membandingkan durasi dari hasilnya dengan durasi lagu aktif secara lokal. Audio tidak dikirim; akses tidak memakai login atau cookie.

Judul harus sama setelah normalisasi, termasuk penghapusan akhiran promosi. Jika salah satu nama artis atau alias cocok setelah normalisasi, toleransi durasinya ±2 detik. Jika artis tidak cocok, misalnya karena perbedaan aksara, hasil hanya diterima bila tepat satu kandidat memiliki judul sama dan durasi dalam ±1 detik. Listener membuang baris kredit di awal isi baris, tetapi mempertahankan timestamp lirik. Hasil instrumental, tanpa lirik, atau hanya kredit tidak ditampilkan sebagai lirik.

Lookup menunggu metadata stabil selama 1 detik; fallback judul/artis tetap berubah segera. Request kedua layanan berjarak minimal 200 ms dan memakai cooldown terpisah per host agar gangguan LRCLIB tidak menghalangi NetEase. Jika keduanya belum memberi hasil dan salah satunya gagal sementara, listener menjadwalkan maksimal tiga retry dengan jeda minimum 15, 30, lalu 60 detik, mengikuti `Retry-After` bila lebih lama.

## Tes

```bash
bats tests/ && shellcheck -x -S warning eww/scripts/lib.sh eww/scripts/media eww/scripts/position eww/scripts/island eww/scripts/marquee eww/scripts/viz eww/scripts/alert eww/scripts/status eww/scripts/weather eww/scripts/scroll openbox/island.sh
python -m unittest discover -s tests -p 'test_lyrics.py'
```

## Debug

- `~/.cache/eww-island.log`: log daemon island, termasuk diagnostik `viz:` (dependensi hilang atau worker audio berhenti) dan stderr `lyrics:` (lookup/cache gagal)
- `eww --config ~/.config/eww-island state`
- `$XDG_RUNTIME_DIR/eww-island/`: state controller (`auto_until`, `player`, `marquee_at` dalam desidetik, `media.json` berisi metadata terakhir)
- `$XDG_RUNTIME_DIR/eww-island/viz.XXXXXXXX/`: direktori privat sementara visualizer berisi FIFO `events`, `frames`, dan `pcm`, dibersihkan saat listener berhenti. Jika `XDG_RUNTIME_DIR` tidak tersedia, state dan direktori ini berada di `/tmp/eww-island/`.
- `${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/lyrics/`: cache lirik LRCLIB/NetEase (format versi 2), terpisah dari cache cover.

## Batasan

- MPRIS Edge/Chromium tidak memberi URL tab: YouTube biasa atau media web lain dari Edge juga tampil.
- Tab Edge dapat berbagi stream audio dalam proses yang sama; visualizer tidak dapat menjamin isolasi audio per tab. Aplikasi yang stream-nya tidak cocok dengan PID player aktif atau turunannya menampilkan bar rata.
- Progress hanya tampilan (tanpa seek); tidak ada like/dislike atau slider volume. Volume diubah lewat scroll pada island ringkas.
- Cakupan lirik bergantung pada LRCLIB/NetEase dan kecocokan versi rekaman; aturan pencocokan NetEase dijelaskan di atas. LRCLIB mensyaratkan judul/artis cocok dengan durasi dalam toleransi ±2 detik; pencocokan artis menerima alias dalam tanda kurung dan nama kolaborator. Sinkronisasi per baris, bukan per kata; intro tambahan pada video YouTube dapat menggeser waktu lirik meskipun metadata cocok.
- Hanya monitor 0.
- Island hanya jalan saat panel aktif adalah eww (dipanggil dari `eww.sh` openbox-omp).
- Cover http diunduh sekali (timeout 3 detik) ke `~/.cache/eww-island/art`, tanpa batas ukuran cache.
