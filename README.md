# openbox-island

Notch ala Dynamic Island untuk Openbox (eww): now playing YouTube Music atau player MPRIS lain (cover, visualizer audio, kontrol).

## Pasang

```bash
git clone https://github.com/ardzz/openbox-island.git && cd openbox-island
sudo pacman -S --needed playerctl jq curl xdotool cava pipewire-audio libpulse inotify-tools
ln -s "$PWD/eww" ~/.config/eww-island
ln -s "$PWD/openbox/island.sh" ~/.config/openbox/island.sh
```

Visualizer memerlukan sesi audio PipeWire aktif dengan layanan kompatibilitas PulseAudio (`pipewire-pulse`), serta `busctl` dari systemd (sudah termasuk sistem dasar Arch). Jika dependensi visualizer belum terpasang saat island dimulai, pasang dependensinya lalu jalankan ulang `~/.config/openbox/island.sh` agar listener visualizer aktif.

Island dijalankan otomatis oleh `openbox/eww.sh` dari openbox-omp setiap bar eww dibuka (termasuk ganti tema). Manual: `~/.config/openbox/island.sh`.

Warna dan font island mengikuti palet tema bar (`~/.config/eww/_colors.scss`), yang disalin setiap kali `island.sh` dimulai. Tanpa palet bar, island memakai palet default hitam.

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

- Idle: island berupa pill kecil kosong. Jam ada di bar. Ada musik: cover + judul + enam bar spektrum audio nyata dalam island 480×36 px. Visualizer diproses pada 20 fps; frame yang tidak berubah tidak dikirim ulang. Bar rata setinggi 4 px saat hening, pause, tidak ada stream yang cocok, atau terjadi error; tidak ada animasi pengganti.
- Hover: membesar menjadi 480×180 px setelah pointer diam di atas island selama 0,3 detik (cover, judul, artis, progress, ⏮ ⏯ ⏭). Ganti lagu: membesar 4 detik lalu menciut; selama pointer di atas island, ganti lagu tidak menciutkannya.
- Saat membesar, judul lebih dari 30 karakter dan artis lebih dari 36 karakter bergulir sekitar 5 karakter/detik, dengan jeda 1,2 detik di awal tiap putaran dan pemisah `   ·   `. Teks pendek tetap diam; guliran dimulai ulang saat window dibuka atau lagu berganti, tanpa polling saat menciut.
- Hover dibaca dari posisi pointer (`xdotool`), bukan dari urutan event enter/leave eww: event itu juga muncul saat aplikasi lain meng-grab pointer dan bisa diproses tidak berurutan.
- Visualizer hanya mengambil stream keluaran milik PID player MPRIS aktif atau proses turunannya, bukan mikrofon, monitor audio sistem, atau sumber audio default sebagai fallback. Metadata dan kontrol MPRIS tetap bekerja jika visualizer tidak mendapat audio.
- Audio visualizer hanya lewat memori/FIFO lokal, tidak disimpan atau diunggah. Unduhan cover tetap menggunakan jaringan.

## Tes

```bash
bats tests/ && shellcheck -x -S warning eww/scripts/lib.sh eww/scripts/media eww/scripts/position eww/scripts/island eww/scripts/marquee eww/scripts/viz openbox/island.sh
```

## Debug

- `~/.cache/eww-island.log`: log daemon island, termasuk diagnostik `viz:` (dependensi hilang atau worker audio berhenti)
- `eww --config ~/.config/eww-island state`
- `$XDG_RUNTIME_DIR/eww-island/`: state controller (`auto_until`, `player`, `marquee_at` dalam desidetik, `media.json` berisi metadata terakhir)
- `$XDG_RUNTIME_DIR/eww-island/viz.XXXXXXXX/`: direktori privat sementara visualizer berisi FIFO `events`, `frames`, dan `pcm`, dibersihkan saat listener berhenti. Jika `XDG_RUNTIME_DIR` tidak tersedia, state dan direktori ini berada di `/tmp/eww-island/`.

## Batasan

- MPRIS Edge/Chromium tidak memberi URL tab: YouTube biasa atau media web lain dari Edge juga tampil.
- Tab Edge dapat berbagi stream audio dalam proses yang sama; visualizer tidak dapat menjamin isolasi audio per tab. Aplikasi yang stream-nya tidak cocok dengan PID player aktif atau turunannya menampilkan bar rata.
- Progress hanya tampilan (tanpa seek); tidak ada like/dislike atau slider volume.
- Hanya monitor 0.
- Island hanya jalan saat panel aktif adalah eww (dipanggil dari `eww.sh` openbox-omp).
- Cover http diunduh sekali (timeout 3 detik) ke `~/.cache/eww-island/art`, tanpa batas ukuran cache.
