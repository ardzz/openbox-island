# Debug, tes, dan batasan

Menjalankan tes dan pratinjau, lokasi log dan state untuk debug, batasan yang diketahui, serta pemecahan masalah umum.

[README](../README.md) · [Fitur](fitur.md) · [Konfigurasi](konfigurasi.md) · [Debug dan tes](debug.md) · [Arsitektur](architecture.md)

## Tes

```bash
bats -r tests/
tools/check
python -m unittest discover -s tests -p 'test_*.py'
```

`tools/check [ROOT]` memeriksa file yang di-track di `eww/`, `openbox/`, `tools/`, dan `tests/`: lebih dari 200 baris `WARN`, lebih dari 300 baris `FAIL` (kecuali `*.conf`, `eww/players`, `eww/shortcuts`, dan gambar), `shellcheck -x -S warning` untuk skrip bash, dan `py_compile` untuk Python. Keluar 1 bila ada FAIL atau error lint.

`tools/preview CONFIG_DIR SAMPLE OUT.png` merender satu jendela island dari keadaan contoh di `tools/samples/*.vars` (baris `window=`, opsional `tab=`, lalu `var=<json>`; `@ASSETS@` menunjuk `tools/samples/assets/`). Salinan konfigurasi di `/tmp` memakai defvar sebagai ganti listener/poll, tanpa animasi, dengan latar abu-abu, dan dibuka 300px di bawah tepi atas pada `DISPLAY` aktif dengan daemon dan runtime dir privat:

```bash
for f in tools/samples/*.vars; do tools/preview eww "$f" ~/.cache/island-baseline/"$(basename "$f" .vars)".png; done
```

Arsitektur, kontrak area, dan resep menambah tab/alert/listener: [docs/architecture.md](architecture.md).

## Debug

- `~/.cache/eww-island.log`: log daemon island, termasuk diagnostik `viz:` (dependensi hilang atau worker audio berhenti) dan stderr `lyrics:` (lookup/cache gagal)
- `eww --config ~/.config/eww-island state`
- `$XDG_RUNTIME_DIR/eww-island/`: state controller (`auto_until`, `player`, `marquee_at` dalam desidetik, `media.json` berisi metadata terakhir, `tab` berisi tab kartu yang terakhir dipilih, `tab_at` berisi waktu perpindahan tab lewat scroll terakhir dalam desidetik, `ytm.json` berisi status tombol suka dan lagu berikutnya terakhir, `ytm_set` berisi hasil klik terakhir untuk listener, `ytm-browser.json` berisi status terakhir dari bridge YouTube Music Edge dengan `ts` waktu terima dalam epoch milidetik)
- `$XDG_RUNTIME_DIR/eww-island/notify.fifo`: FIFO listener notifikasi; menerima satu baris JSON per notifikasi dari `notify-hook` serta sinyal `@alert 0|1`, `@expanded 0|1`, dan `@click ID`. Kirim notifikasi uji dengan `notify-send Tes 'isi'`.
- `$XDG_RUNTIME_DIR/eww-island/notif.fifo`: FIFO pusat notifikasi; menerima `@refresh`, `@expanded 0|1`, `@tab NAMA`, dan `@scroll -1|1`. `notif_seen` berisi waktu tab Notifikasi terakhir dilihat (mikrodetik sejak boot, jam yang sama dengan timestamp dunst), `notif_entries` berisi desktop entry per ID notifikasi dari `notify-hook`.
- `$XDG_RUNTIME_DIR/eww-island/todo.fifo`: FIFO daftar tugas; menerima `@refresh`, `@expanded 0`, dan `@scroll -1|1`.
- `$XDG_RUNTIME_DIR/eww-island/viz.XXXXXXXX/`: direktori privat sementara visualizer berisi FIFO `events`, `frames`, dan `pcm`, dibersihkan saat listener berhenti. Jika `XDG_RUNTIME_DIR` tidak tersedia, state dan direktori ini berada di `/tmp/eww-island/`.
- `${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/lyrics/`: cache lirik YouTube Music/LRCLIB/NetEase (format versi 2), terpisah dari cache cover.

## Batasan

- MPRIS Edge tidak memberi URL tab. Edge hanya tampil bila bridge YouTube Music terpasang dan statusnya baru serta judulnya cocok ([Fitur → Musik](fitur.md#musik)); YouTube biasa dan media web lain dari Edge tidak tampil. Player di luar `ytm_player`, `ytermusic`, dan `edge` tidak pernah tampil.
- Tab Edge dapat berbagi stream audio dalam proses yang sama; visualizer tidak dapat menjamin isolasi audio per tab. Aplikasi yang stream-nya tidak cocok dengan PID player aktif atau turunannya menampilkan bar rata.
- Progress hanya tampilan; seek hanya lewat klik baris lirik tersinkron di mode Lirik. Tidak ada slider volume. Volume diubah lewat scroll pada island ringkas. Like/dislike hanya untuk ytm-player; klik dianggap berhasil bila `ytm` sukses, tanpa membaca ulang status dari YouTube Music.
- Berpindah tab dengan scroll/geser horizontal (touchpad dua jari, tilt wheel) tidak didukung: `onscroll` eww hanya meneruskan scroll vertikal (`up`/`down`) dan membuang event horizontal, dan Shift+scroll tidak bisa dibedakan dari scroll biasa. Pakai klik atau scroll vertikal di atas baris tab.
- Cakupan lirik bergantung pada YouTube Music (khusus `ytm_player`), LRCLIB/NetEase, dan kecocokan versi rekaman; aturan pencocokan NetEase dijelaskan di [Fitur → Fallback lirik NetEase](fitur.md#fallback-lirik-netease). LRCLIB mensyaratkan judul/artis cocok dengan durasi dalam toleransi ±2 detik; pencocokan artis menerima alias dalam tanda kurung dan nama kolaborator. Sinkronisasi per baris, bukan per kata; intro tambahan pada video YouTube dapat menggeser waktu lirik meskipun metadata cocok. Lirik YouTube Music tanpa timestamp hanya perkiraan posisi, bukan sinkron.
- Hanya monitor 0.
- Island hanya jalan saat panel aktif adalah eww (dipanggil dari `eww.sh` openbox-omp).
- Cover http diunduh sekali (timeout 3 detik) ke `~/.cache/eww-island/art`, tanpa batas ukuran cache.
- Aksi asli notifikasi yang popup-nya disembunyikan (misalnya membuka chat tertentu) tidak dapat dijalankan: dunst sudah menutup notifikasi tersebut di D-Bus saat menyembunyikannya, sehingga klik hanya mengaktifkan atau menjalankan aplikasinya.
- Jika daemon island berhenti tanpa `island.sh stop`, drop-in dunst tetap terpasang: popup notifikasi normal tetap tersembunyi (hanya masuk riwayat dunst) sampai island dijalankan ulang atau dihentikan.

## Pemecahan masalah

- Visualizer rata terus: cek baris `viz:` di `~/.cache/eww-island.log`. Jika dependensi visualizer baru dipasang setelah island dimulai, jalankan ulang `~/.config/openbox/island.sh` ([Konfigurasi → Dependensi](konfigurasi.md#dependensi)). Stream player yang tidak cocok juga menampilkan bar rata ([Fitur → Visualizer](fitur.md#visualizer)).
- Lirik tidak muncul: cek stderr `lyrics:` di log dan cache `${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/lyrics/`; urutan sumber ada di [Fitur → Lirik](fitur.md#lirik).
- Bayangan persegi di sekitar island: tambahkan rule picom di [Konfigurasi → picom](konfigurasi.md#picom).
- Tombol suka tidak tampil: periksa login ytm-player dan `ytmusicapi` ([Konfigurasi → Tombol suka YouTube Music](konfigurasi.md#tombol-suka-youtube-music)).
- Musik dari Edge tidak tampil: pastikan ekstensi `browser/ytm-bridge` aktif dan installer dijalankan dengan ID ekstensi yang sama ([Konfigurasi → Bridge YouTube Music untuk Edge](konfigurasi.md#bridge-youtube-music-untuk-edge)), lalu muat ulang tab YouTube Music. Selama tab YouTube Music punya lagu, `ts` di `$XDG_RUNTIME_DIR/eww-island/ytm-browser.json` diperbarui kira-kira setiap 5 detik.
- Island hilang saat aplikasi layar penuh: perilaku bawaan, matikan dengan `ISLAND_FULLSCREEN_HIDE=0` ([Fitur → Layar penuh](fitur.md#layar-penuh)).
- Popup dunst tetap tersembunyi setelah island mati: jalankan `~/.config/openbox/island.sh stop` untuk menghapus drop-in ([Konfigurasi → Integrasi dunst](konfigurasi.md#integrasi-dunst)).
- Notifikasi uji: `notify-send Tes 'isi'`; state island dapat dilihat dengan `eww --config ~/.config/eww-island state`.
