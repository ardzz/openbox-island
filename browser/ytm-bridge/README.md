# Bridge YouTube Music untuk Edge

1. Buka `edge://extensions`, aktifkan Mode pengembang, lalu pilih **Load unpacked**
   dan folder `browser/ytm-bridge` dari repositori ini.
2. Salin ID ekstensi. Jalankan `./install.sh ID_EKSTENSI` dari folder ini,
   atau isi `YTM_BRIDGE_EXT_ID` sebelum menjalankan installer.
3. Muat ulang ekstensi dan buka atau muat ulang `https://music.youtube.com/`.

Diperlukan Bash, jq (jaq juga didukung), dan utilitas GNU coreutils.
Installer mendaftarkan native host hanya untuk ID ekstensi tersebut di
`~/.config/microsoft-edge/NativeMessagingHosts/`. Path host mengikuti lokasi
repositori; jalankan installer lagi jika repositori dipindah.

Ekstensi hanya membaca metadata Media Session, parameter URL `v`, dan status
pemutaran setiap detik. Perubahan dikirim segera pada polling berikutnya;
metadata yang sama dikirim ulang setiap lima detik. Tidak ada klik, autoplay,
atau perintah pemutaran dari bridge.

Service worker memilih satu tab sumber: tab yang sedang memutar didahulukan;
jika semuanya dijeda, tab yang terakhir memutar atau dijeda tetap dipilih.
Heartbeat tab lain tidak menimpa sumber tersebut. Menutup tab sumber
memilih tab lain yang tersisa. Hanya metadata sumber terpilih diteruskan ke native host.
Kandidat Edge yang belum lolos bukti bridge diperiksa ulang setiap 250 ms
selama belum ditampilkan, sehingga heartbeat baru dapat memulihkannya tanpa
perubahan metadata MPRIS. Pemulihan lagu yang sedang memutar membuka island
seperti awal lagu baru; aturan pembaruan pertama untuk lagu yang langsung lolos tetap berlaku.
Host memvalidasi objek JSON
dengan `title` dan `artist` bertipe string serta `ts` opsional bertipe angka,
lalu mengganti `ts` dengan waktu penerimaan dalam epoch milidetik. Status
`{title, artist, album, video_id, playing, ts}` ditulis secara atomik ke
`$XDG_RUNTIME_DIR/eww-island/ytm-browser.json` (fallback `/tmp/eww-island`).
Pesan tidak valid diabaikan tanpa mengubah status terakhir.
