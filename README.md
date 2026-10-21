# openbox-island

Notch ala Dynamic Island untuk Openbox (eww): now playing YouTube Music atau player MPRIS lain (cover dan kontrol).

## Pasang

```bash
git clone https://github.com/ardzz/openbox-island.git && cd openbox-island
sudo pacman -S --needed playerctl jq curl xdotool
ln -s "$PWD/eww" ~/.config/eww-island
ln -s "$PWD/openbox/island.sh" ~/.config/openbox/island.sh
```

Island dijalankan otomatis oleh `openbox/eww.sh` dari openbox-omp setiap bar eww dibuka (termasuk ganti tema). Manual: `~/.config/openbox/island.sh`.

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

- Idle: island berupa pill kecil kosong. Jam ada di bar. Ada musik: cover + judul dalam island 480×36 px.
- Hover: membesar menjadi 480×180 px setelah pointer diam di atas island selama 0,3 detik (cover, judul, artis, progress, ⏮ ⏯ ⏭). Ganti lagu: membesar 4 detik lalu menciut; selama pointer di atas island, ganti lagu tidak menciutkannya.
- Hover dibaca dari posisi pointer (`xdotool`), bukan dari urutan event enter/leave eww: event itu juga muncul saat aplikasi lain meng-grab pointer dan bisa diproses tidak berurutan.

## Tes

```bash
bats tests/ && shellcheck -x -S warning eww/scripts/lib.sh eww/scripts/media eww/scripts/position eww/scripts/island openbox/island.sh
```

## Debug

- `~/.cache/eww-island.log`: log daemon island
- `eww --config ~/.config/eww-island state`
- `$XDG_RUNTIME_DIR/eww-island/`: state controller (`auto_until`, `player`). Jika `XDG_RUNTIME_DIR` tidak tersedia, state berada di `/tmp/eww-island/`.

## Batasan

- MPRIS Edge/Chromium tidak memberi URL tab: YouTube biasa atau media web lain dari Edge juga tampil.
- Progress hanya tampilan (tanpa seek); tidak ada like/dislike atau slider volume.
- Hanya monitor 0.
- Island hanya jalan saat panel aktif adalah eww (dipanggil dari `eww.sh` openbox-omp).
- Cover http diunduh sekali (timeout 3 detik) ke `~/.cache/eww-island/art`, tanpa batas ukuran cache.
