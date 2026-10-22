# openbox-island

Notch ala Dynamic Island untuk Openbox (eww): now playing YouTube Music atau player MPRIS lain (cover, lirik tersinkron, visualizer audio, kontrol), notifikasi dunst, alert volume/kecerahan/baterai/Wi-Fi/Bluetooth/VPN/tangkapan layar/suhu/Caps Lock, indikator mikrofon/kamera/Jangan Ganggu/VPN/perekaman layar, dan cuaca.

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

Urutan prioritas ada di `eww/players` (default `ytm_player,ytermusic,edge,%any`; `ytm_player` adalah [ytm-player](https://ytm-player.com)): nama player MPRIS dipisah koma, `%any` = player lain. Lihat nama player: `playerctl -l`. Setelah mengubah, jalankan ulang `~/.config/openbox/island.sh`.

Tombol suka/tidak suka YouTube Music memerlukan [ytm-player](https://ytm-player.com) (CLI `ytm`, nama MPRIS `ytm_player`) yang sudah login, serta paket Python `ytmusicapi` untuk membaca status suka. Login dibaca dari `~/.config/ytm-player/auth.json` (ubah dengan `OB_YTM_AUTH`). Tanpa keduanya tombol tidak tampil.

## Perilaku

- Idle: island tetap berupa pill kecil dengan cuaca dan indikator aktivitas; jika tidak ada informasi, pill tetap terlihat kosong. Jam ada di bar. Ada musik: cover + satu baris lirik + enam bar spektrum audio nyata serta indikator aktivitas dalam island 480×36 px. Visualizer diproses sesuai refresh rate monitor island saat ini (mode aktif `xrandr` pada output di titik 0,0 atau primary; dibulatkan, 1–240 fps, 60 fps bila tidak terbaca), dengan 13 tingkat tinggi bar (4–16 px, langkah 1 px); `ISLAND_VIZ_FPS` (bilangan bulat 1–240) menimpanya. Refresh rate dibaca ulang setiap kali capture audio dimulai ulang (ganti player/stream), tanpa polling. Frame yang tidak berubah tidak dikirim ulang. Bar rata setinggi 4 px saat hening, pause, tidak ada stream yang cocok, atau terjadi error; tidak ada animasi pengganti.
- Hover: membesar menjadi 480×210 px setelah pointer diam di atas island selama 0,3 detik (cover, judul, artis, satu baris lirik, progress, lagu berikutnya untuk YouTube Music, ⏮ ⏯ ⏭). Ganti lagu: membesar 4 detik lalu menciut; selama pointer di atas island, ganti lagu tidak menciutkannya.
- YouTube Music: selama player yang tampil adalah `ytm_player`, kontrol diapit tombol tidak suka (kiri) dan suka (kanan). Status suka lagu dibaca sekali per lagu di latar belakang lewat ytmusicapi (`get_watch_playlist`, sekitar 1,5 detik) dan disimpan selama listener berjalan; jawaban lambat untuk lagu sebelumnya diabaikan. Tombol yang aktif terisi dan berwarna aksen. Klik menjalankan `ytm like`/`ytm dislike`, atau `ytm unlike` bila status itu sudah aktif, lalu tampilan langsung berubah. Listener mengikuti state `scripts/media` lewat `inotifywait`, tanpa polling; `ytm status` dipanggil sekali saat lagu berganti untuk mengambil video ID.
- Lagu berikutnya: selama tombol suka tampil, di bawah progress ada satu baris redup `Berikutnya: judul — artis`, dipotong dengan elipsis bila melebihi lebar kartu. Antrean dibaca sekali per lagu dengan `ytm queue` (hanya baca) di latar belakang setelah video ID didapat; jawaban untuk lagu sebelumnya diabaikan dan baris lama langsung hilang saat lagu berganti. Lagu berikutnya dipilih seperti ytm-player sendiri: entri sesudah `current_index`, lagu yang sama saat repeat one, entri pertama saat repeat all tanpa shuffle di akhir antrean. Baris tidak tampil bila lagu yang diputar adalah entri terakhir (termasuk akhir antrean shuffle, karena urutan diacak ulang), tidak berada di posisi `current_index`, atau antrean gagal dibaca. Perubahan antrean tanpa ganti lagu baru terlihat pada lagu berikutnya.
- Saat membesar, judul lebih dari 30 karakter dan artis lebih dari 36 karakter bergulir sekitar 5 karakter/detik, dengan jeda 1,2 detik di awal tiap putaran dan pemisah `   ·   `. Teks pendek tetap diam; guliran dimulai ulang saat window dibuka atau lagu berganti, tanpa polling saat menciut.
- Hover dibaca dari posisi pointer (`xdotool`), bukan dari urutan event enter/leave eww: event itu juga muncul saat aplikasi lain meng-grab pointer dan bisa diproses tidak berurutan.
- Visualizer hanya mengambil stream keluaran milik PID player MPRIS aktif atau proses turunannya, bukan mikrofon, monitor audio sistem, atau sumber audio default sebagai fallback. Metadata dan kontrol MPRIS tetap bekerja jika visualizer tidak mendapat audio.
- Audio visualizer hanya lewat memori/FIFO lokal, tidak disimpan atau diunggah. Unduhan cover tetap menggunakan jaringan.
- Lirik tersinkron dari LRCLIB, dengan NetEase Cloud Music sebagai fallback, tampil miring dan rata tengah pada kedua ukuran island. Untuk `ytm_player`, lirik YouTube Music dicoba lebih dulu (lihat [Lirik YouTube Music](#lirik-youtube-music)). Baris panjang dipotong dengan elipsis, tanpa bergulir atau mengecilkan font; tooltip menampilkan teks lengkap. Posisi MPRIS dibaca setiap 250 ms saat player aktif; listener hanya mengirim perubahan teks/status sinkron, bukan frame berulang. Saat belum ada baris lirik, intro, instrumental, hasil tidak tersedia, atau lookup gagal/timeout tanpa cache positif, judul dan artis asli tampil dengan warna redup.
- LRCLIB tidak memerlukan API key. Pencarian mengirim metadata judul, artis, dan durasi, bukan audio. Cache hasil positif berlaku 30 hari; hasil positif kedaluwarsa masih dipakai jika layanan gagal diakses. Cache negatif berlaku 24 jam hanya jika semua sumber yang dicoba memastikan tidak ada lirik tersinkron; cache negatif yang dibuat tanpa YouTube Music tidak berlaku untuk `ytm_player`. Error jaringan/timeout tidak disimpan sebagai hasil negatif.

## Aktivitas

Alert menggantikan isi pill sementara, hanya pada tampilan ringkas; tampilan yang sedang membesar tidak berubah. Alert volume, mikrofon, kecerahan, dan Caps Lock bertahan 1,5 detik; alert lain bertahan 3 detik.

| Jenis | Teks |
| --- | --- |
| `volume` | `Volume` atau `Bisu`, dengan persentase volume |
| `mic` | `Mikrofon nyala` atau `Mikrofon mati` |
| `output` | `Output audio` saat sink default atau port aktifnya berganti, dengan nama port aktif (jika sink punya lebih dari satu port) atau nama sink; ikon headphone Bluetooth, headphone, monitor (HDMI/DisplayPort), atau speaker |
| `brightness` | `Kecerahan`, dengan persentase |
| `charging` | `Mengisi daya` saat charger dipasang, dengan persentase (ditambah `· batas 80%` selama mode konservasi aktif); ikon berwarna aksen dan berdenyut beberapa kali |
| `battery` | `Charger dicabut` atau `Baterai penuh`, dengan persentase; juga `Batas pengisian aktif` (80%) atau `Pengisian penuh` (100%) saat mode konservasi baterai Lenovo berubah |
| `battery-low` | `Baterai lemah` saat melewati 20% atau `Baterai kritis` saat melewati 10% ketika daya sedang dipakai; ikon dan meter berwarna merah |
| `wifi` | `Wi-Fi tersambung` dengan nama koneksi, atau `Wi-Fi terputus` |
| `bluetooth` | `Bluetooth tersambung` atau `Bluetooth terputus`, dengan nama perangkat (alias) serta persentase baterai saat tersambung jika perangkat melaporkannya; ikon mengikuti jenis perangkat (headphone, gamepad, mouse, keyboard, ponsel) |
| `vpn` | `VPN tersambung` atau `VPN terputus` dengan nama interface, satu alert per interface; `Tailscale tersambung` dengan nama host perangkat ini, atau `Tailscale terputus`; `Exit node aktif` dengan nama exit node, atau `Exit node dimatikan` |
| `vpn-error` | `Tailscale perlu login` saat Tailscale meminta login atau persetujuan perangkat; ikon berwarna merah |
| `screenshot` | `Tangkapan layar` dengan nama berkas dan thumbnail gambar sebagai pengganti ikon, saat berkas `.png`/`.jpg`/`.jpeg` baru selesai ditulis atau dipindahkan ke folder tangkapan layar |
| `temperature` | `CPU panas` atau `GPU panas` dengan suhunya, sekali saat suhu mencapai batas (CPU 95 °C, GPU 87 °C; ubah dengan `ISLAND_TEMP_CPU`/`ISLAND_TEMP_GPU`); muncul lagi hanya setelah suhu turun di bawah batas − 5 °C. Ikon berwarna merah |
| `capslock` | `Caps Lock nyala` atau `Caps Lock mati` saat status LED Caps Lock keyboard (`/sys/class/leds/*::capslock`, dibaca setiap 0,25 detik) berubah |
| `power` | `Mode daya` dengan nama mode (`Hemat daya`, `Seimbang`, `Performa`, `Daya maksimum`, `Kustom`; nilai lain apa adanya) dan ikon per mode, saat profil daya ACPI (`/sys/firmware/acpi/platform_profile`, misalnya lewat Fn+Q di Lenovo Legion; dibaca setiap 2 detik, ubah dengan `ISLAND_POWER_INTERVAL`) berubah |

Folder tangkapan layar: `ISLAND_SCREENSHOT_DIR` jika diset, selain itu `$(xdg-user-dir PICTURES)/Screenshots`, sama dengan `ob-screenshot`/Satty. Jika folder Gambar XDG belum diatur, `xdg-user-dir` menjawab `$HOME`, sehingga folder yang dipantau adalah `~/Screenshots`. Folder dibuat jika belum ada.

Suhu dibaca langsung dari hwmon (`/sys/class/hwmon`) setiap 5 detik (`ISLAND_TEMP_INTERVAL`), tanpa `sensors` atau `nvidia-smi` agar GPU diskrit tidak terbangun. Sensor CPU berlabel `CPU Temperature`, `Package id 0`, atau `Tctl` (urutan prioritas); sensor GPU berlabel `GPU Temperature`. Tanpa sensor yang cocok, alert suhu tidak aktif. Saat island dimulai dalam kondisi sudah panas, alert baru muncul setelah suhu turun lalu naik lagi.

Mode konservasi baterai Lenovo dibaca dari `ISLAND_CONSERVATION` jika diset, selain itu dari `/sys/bus/platform/devices/VPC2004:*/conservation_mode`, setiap 5 detik (`ISLAND_CONSERVATION_INTERVAL`). Status saat island dimulai tidak memunculkan alert. Tanpa berkas tersebut, alert konservasi tidak aktif dan alert `charging` tidak berubah.

VPN diperiksa setiap 10 detik (`ISLAND_VPN_INTERVAL`). VPN umum dibaca langsung dari `/sys/class/net`: interface tun (bukan tap, agar interface VM seperti `vnet0` tidak terhitung), WireGuard, atau `ppp*` yang tidak berstatus `down`; `tailscale*` dikecualikan. Tailscale dibaca dengan `tailscale status --json` tanpa root; nama exit node dicari hanya saat exit node berganti. Tanpa `tailscale` atau saat daemon mati, Tailscale dianggap tidak tersambung tanpa pesan error. Kondisi saat island dimulai tidak memunculkan alert.

Notifikasi dunst tampil di pill ringkas menggantikan isi idle atau media (musik tetap berjalan): ikon aplikasi (gambar dari path ikon notifikasi, selain itu ikon lonceng), ringkasan tebal, dan satu baris isi yang dipotong dengan elipsis. Markup dibuang dan entitas HTML diubah menjadi teks biasa. Tiap notifikasi bertahan 4 detik (`ISLAND_NOTIFY_SECONDS`), lalu tampilan sebelumnya kembali. Notifikasi berikutnya antre dan tampil bergantian; jika lebih dari tiga menunggu, sisanya digabung menjadi satu entri `+N notifikasi` di akhir antrean. Pembaruan dengan ID yang sama, atau notifikasi dari aplikasi dengan stack tag yang sama, menggantikan entri lama di tempatnya. Alert selalu didahulukan: notifikasi yang sedang tampil berhenti menghitung selama alert tampil lalu melanjutkan sisa waktunya, dan notifikasi baru menunggu sampai alert hilang. Selama island membesar, notifikasi ditunda dengan cara yang sama sampai island menciut; hover di atas notifikasi tidak membesarkan island. Saat Jangan Ganggu dunst aktif, notifikasi tidak tampil di island.

Notifikasi kritis tetap muncul sebagai popup dunst, dan pill-nya diberi aksen merah. Klik pada notifikasi menutupnya dari island (popup notifikasi kritis ikut ditutup) dan membuka aplikasinya: window aplikasi yang terlihat diaktifkan dengan `xdotool`, dicari lewat `StartupWMClass` desktop entry, ID desktop entry, lalu nama aplikasi; jika tidak ada window dan notifikasi membawa desktop entry, aplikasi dijalankan dengan `gtk-launch`. Klik pada `+N notifikasi` hanya menutupnya.

Indikator tampil pada pill idle dan media: titik merah dengan durasi berarti layar sedang direkam, titik kuning berarti mikrofon dipakai, titik hijau berarti kamera dipakai, ikon lonceng dicoret berarti Jangan Ganggu dunst aktif, dan ikon perisai gembok berarti lalu lintas lewat VPN (VPN umum tersambung atau exit node Tailscale aktif; jaringan Tailscale saja tidak menyalakannya). Tooltip mikrofon dan kamera mencantumkan aplikasi yang memakainya; tooltip VPN menyebut interface dan exit node, misalnya `VPN: tekna0, Tailscale via exit-jkt`. Deteksi kamera hanya melihat proses milik pengguna yang sama.

Perekaman layar terdeteksi dari proses milik pengguna yang sama: `ffmpeg` dengan format input `-f x11grab` atau `-f kmsgrab`, atau OBS (`obs` maupun helper `obs-ffmpeg-mux`) yang sedang menulis berkas `.mkv`/`.mp4`/`.mov`/`.flv`/`.ts`/`.webm`. Saat tidak merekam, `/proc` diperiksa setiap 2 detik (`ISLAND_REC_INTERVAL`); selama merekam, durasi sejak rekaman pertama terdeteksi diperbarui setiap detik dan tooltip menyebut aplikasinya.

Scroll ke atas/bawah di atas island ringkas mengubah volume keluaran default sebesar ±5%. Perubahan ini sekaligus membuka bisu (unmute), dengan batas 0–100%.

Jika `dunstctl` tersedia, setelah window island berhasil dibuka launcher memasang drop-in `${XDG_CONFIG_HOME:-$HOME/.config}/dunst/dunstrc.d/50-eww-island-osd.conf` lalu memuat ulang dunst. Drop-in ini menyembunyikan popup notifikasi normal dan rendah (tetap tersimpan di riwayat dunst) dan menyerahkan setiap notifikasi ke `scripts/notify-hook` lewat opsi `script` dunst; notifikasi kritis dan kegagalan launcher (aplikasi `eww-island`) tetap tampil sebagai popup. Hook memerlukan `always_run_script = true` di dunst (nilai default). Notifikasi bertag `obvolume` dan `obbacklight` disembunyikan termasuk dari riwayat agar OSD tidak muncul dua kali. `island.sh stop` menghapus drop-in tersebut dan memuat ulang dunst; restart juga menghapus aturan lama sebelum memasang ulang. Kegagalan pemasangan atau reload dunst tidak menggagalkan launcher.

Cuaca berasal dari wttr.in. Pill idle menampilkan ikon, suhu, dan kota, rata tengah. Hover di atas island idle selama 0,3 detik membuka kartu detail 480×210 px: kondisi cuaca, suhu, kota dan wilayah, waktu matahari terbit/terbenam, suhu terasa, kelembapan, angin, indeks UV, serta prakiraan 3 hari dengan suhu maksimum/minimum dan peluang hujan. Jika cuaca tidak tersedia, hover idle tidak membuka kartu. Cuaca diperbarui setiap 30 menit, dicoba ulang setelah 5 menit jika gagal, dan cache dapat dipakai selama 3 jam.

Warna ikon cuaca (pill, kartu, dan prakiraan) mengikuti kondisi lalu suhu: hujan biru, badai magenta, salju putih, kabut dan berawan abu; selain itu ≥33° merah (panas), ≤15° cyan (dingin), cerah malam biru pucat, ≥28° jingga (hangat), cerah kuning. Prakiraan memakai suhu maksimum dan selalu dianggap siang. Warna berasal dari palet tema bar.

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

Dependensi aktivitas: `pactl` (paket `libpulse`) untuk volume/mikrofon dan scroll; `inotify-tools` untuk pengamatan kamera dan folder tangkapan layar; `dbus` (`dbus-monitor`) untuk status Jangan Ganggu; `dunst` (`dunstctl`) dan `xdotool` untuk notifikasi; `light` untuk kecerahan; `upower` untuk baterai; NetworkManager (`nmcli`) untuk Wi-Fi; serta `curl` dan `jq` untuk cuaca dan data JSON. Opsional: `geoclue` untuk lokasi otomatis sebelum fallback alamat IP; `gdbus` (paket `glib2`) dan `bluetoothctl` (paket `bluez-utils`) untuk alert Bluetooth; `tailscale` untuk alert dan indikator Tailscale; `gtk-launch` (paket `gtk3`) untuk membuka aplikasi dari klik notifikasi saat window-nya belum ada.

## Lirik YouTube Music

Saat player aktif adalah `ytm_player`, listener mengambil video id dari `ytm status` (MPRIS ytm-player tidak membawanya), lalu meminta lirik lewat `ytmusicapi` dengan login ytm-player (`${XDG_CONFIG_HOME:-$HOME/.config}/ytm-player/auth.json`). Lookup berjalan di thread terpisah sehingga pembacaan posisi 250 ms tidak tertahan. Jika `ytmusicapi` tidak terpasang atau `auth.json` tidak ada, sumber ini dilewati tanpa pesan dan LRCLIB/NetEase tetap dipakai.

Urutan prioritas: lirik YouTube Music bertimestamp, lalu lirik tersinkron LRCLIB, NetEase, kemudian lirik YouTube Music biasa (tanpa timestamp), dan terakhir judul/artis. Permintaan bertimestamp yang gagal (misalnya HTTP 400) diulang tanpa timestamp; pada akun yang diuji, YouTube Music hanya memberi lirik biasa.

Lirik biasa tidak tersinkron: baris yang tampil hanya **perkiraan**, yaitu baris lirik dibagi rata sepanjang durasi lagu menurut posisi putar, sehingga bisa mendahului atau tertinggal dari lagu. Baris perkiraan ini tampil dengan warna redup seperti fallback, bukan gaya lirik tersinkron. Lirik biasa disimpan bersama cache negatif selama 24 jam agar sumber tersinkron dicek ulang setelahnya. Kegagalan `ytm status` atau request YouTube Music dianggap gangguan sementara dan mengikuti jadwal retry yang sama.

## Fallback lirik NetEase

Listener mencoba NetEase Cloud Music jika LRCLIB tidak menghasilkan lirik tersinkron yang cocok, termasuk saat LRCLIB gagal sementara. Endpoint NetEase ini tidak resmi dan dapat berubah atau berhenti tersedia. Listener mengirim judul dan artis ke server NetEase untuk pencarian, lalu membandingkan durasi dari hasilnya dengan durasi lagu aktif secara lokal. Audio tidak dikirim; akses tidak memakai login atau cookie.

Judul harus sama setelah normalisasi, termasuk penghapusan akhiran promosi. Jika salah satu nama artis atau alias cocok setelah normalisasi, toleransi durasinya ±2 detik. Jika artis tidak cocok, misalnya karena perbedaan aksara, hasil hanya diterima bila tepat satu kandidat memiliki judul sama dan durasi dalam ±1 detik. Listener membuang baris kredit di awal isi baris, tetapi mempertahankan timestamp lirik. Hasil instrumental, tanpa lirik, atau hanya kredit tidak ditampilkan sebagai lirik.

Lookup menunggu metadata stabil selama 1 detik; fallback judul/artis tetap berubah segera. Request kedua layanan berjarak minimal 200 ms dan memakai cooldown terpisah per host agar gangguan LRCLIB tidak menghalangi NetEase. Jika keduanya belum memberi hasil dan salah satunya gagal sementara, listener menjadwalkan maksimal tiga retry dengan jeda minimum 15, 30, lalu 60 detik, mengikuti `Retry-After` bila lebih lama.

## Tes

```bash
bats tests/ && shellcheck -x -S warning eww/scripts/lib.sh eww/scripts/vpn.sh eww/scripts/media eww/scripts/position eww/scripts/island eww/scripts/marquee eww/scripts/viz eww/scripts/alert eww/scripts/status eww/scripts/rec eww/scripts/weather eww/scripts/scroll eww/scripts/notify eww/scripts/notify-hook eww/scripts/ytm openbox/island.sh
python -m unittest discover -s tests -p 'test_lyrics.py'
python -m unittest discover -s tests -p 'test_ytm_like.py'
```

## Debug

- `~/.cache/eww-island.log`: log daemon island, termasuk diagnostik `viz:` (dependensi hilang atau worker audio berhenti) dan stderr `lyrics:` (lookup/cache gagal)
- `eww --config ~/.config/eww-island state`
- `$XDG_RUNTIME_DIR/eww-island/`: state controller (`auto_until`, `player`, `marquee_at` dalam desidetik, `media.json` berisi metadata terakhir, `ytm.json` berisi status tombol suka dan lagu berikutnya terakhir, `ytm_set` berisi hasil klik terakhir untuk listener)
- `$XDG_RUNTIME_DIR/eww-island/notify.fifo`: FIFO listener notifikasi; menerima satu baris JSON per notifikasi dari `notify-hook` serta sinyal `@alert 0|1`, `@expanded 0|1`, dan `@click ID`. Kirim notifikasi uji dengan `notify-send Tes 'isi'`.
- `$XDG_RUNTIME_DIR/eww-island/viz.XXXXXXXX/`: direktori privat sementara visualizer berisi FIFO `events`, `frames`, dan `pcm`, dibersihkan saat listener berhenti. Jika `XDG_RUNTIME_DIR` tidak tersedia, state dan direktori ini berada di `/tmp/eww-island/`.
- `${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/lyrics/`: cache lirik YouTube Music/LRCLIB/NetEase (format versi 2), terpisah dari cache cover.

## Batasan

- MPRIS Edge/Chromium tidak memberi URL tab: YouTube biasa atau media web lain dari Edge juga tampil.
- Tab Edge dapat berbagi stream audio dalam proses yang sama; visualizer tidak dapat menjamin isolasi audio per tab. Aplikasi yang stream-nya tidak cocok dengan PID player aktif atau turunannya menampilkan bar rata.
- Progress hanya tampilan (tanpa seek); tidak ada slider volume. Volume diubah lewat scroll pada island ringkas. Like/dislike hanya untuk ytm-player; klik dianggap berhasil bila `ytm` sukses, tanpa membaca ulang status dari YouTube Music.
- Cakupan lirik bergantung pada YouTube Music (khusus `ytm_player`), LRCLIB/NetEase, dan kecocokan versi rekaman; aturan pencocokan NetEase dijelaskan di atas. LRCLIB mensyaratkan judul/artis cocok dengan durasi dalam toleransi ±2 detik; pencocokan artis menerima alias dalam tanda kurung dan nama kolaborator. Sinkronisasi per baris, bukan per kata; intro tambahan pada video YouTube dapat menggeser waktu lirik meskipun metadata cocok. Lirik YouTube Music tanpa timestamp hanya perkiraan posisi, bukan sinkron.
- Hanya monitor 0.
- Island hanya jalan saat panel aktif adalah eww (dipanggil dari `eww.sh` openbox-omp).
- Cover http diunduh sekali (timeout 3 detik) ke `~/.cache/eww-island/art`, tanpa batas ukuran cache.
- Aksi asli notifikasi yang popup-nya disembunyikan (misalnya membuka chat tertentu) tidak dapat dijalankan: dunst sudah menutup notifikasi tersebut di D-Bus saat menyembunyikannya, sehingga klik hanya mengaktifkan atau menjalankan aplikasinya.
- Jika daemon island berhenti tanpa `island.sh stop`, drop-in dunst tetap terpasang: popup notifikasi normal tetap tersembunyi (hanya masuk riwayat dunst) sampai island dijalankan ulang atau dihentikan.
