# Fitur

Perilaku island: pill ringkas dan kartu, musik, lirik, visualizer, alert, notifikasi, indikator, serta tab Kalender, Cuaca, Tugas, dan Pintasan.

[README](../README.md) · [Fitur](fitur.md) · [Konfigurasi](konfigurasi.md) · [Debug dan tes](debug.md) · [Arsitektur](architecture.md)

## Pill dan kartu

Island menempel di tepi atas layar seperti notch: sisi atasnya rata dengan tepi layar, sudut bawahnya membulat (16 px; kartu yang membesar 22 px), dan dua "telinga" cekung 14 px di kiri dan kanan atas melengkungkan notch ke tepi layar. Tampilan ringkas berukuran 508×44 px (badan 480 px ditambah dua telinga) dengan tinggi yang sama untuk semua halaman: isi idle, media, dan alert ada di baris 36 px di bawah strip 8 px di tepi layar, sedangkan notifikasi dua baris memakai seluruh tinggi 44 px. Telinga selalu menempel di samping pill yang tampil, termasuk pill idle yang sempit. Kartu yang membesar berukuran 508×218 px dan menempel di tepi atas dengan cara yang sama.

Window island bersifat override-redirect (`:wm-ignore true`), jadi Openbox tidak mengelolanya dan klik pada bar tidak bisa menaikkan bar menutupi island.

- Idle: island tetap berupa pill kecil dengan cuaca dan indikator aktivitas; jika tidak ada informasi, pill tetap terlihat kosong. Jam ada di bar. Ada musik: cover + satu baris lirik + enam bar spektrum audio nyata serta indikator aktivitas dalam notch 508×44 px. Visualizer diproses sesuai refresh rate monitor island saat ini (mode aktif `xrandr` pada output di titik 0,0 atau primary; dibulatkan, 1–240 fps, 60 fps bila tidak terbaca), dengan 13 tingkat tinggi bar (4–16 px, langkah 1 px); `ISLAND_VIZ_FPS` (bilangan bulat 1–240) menimpanya. Refresh rate dibaca ulang setiap kali capture audio dimulai ulang (ganti player/stream), tanpa polling. Frame yang tidak berubah tidak dikirim ulang. Bar rata setinggi 4 px saat hening, pause, tidak ada stream yang cocok, atau terjadi error; tidak ada animasi pengganti.
- Hover: membesar menjadi 508×218 px setelah pointer diam di atas island selama 0,3 detik (cover, judul, artis, satu baris lirik, progress, lagu berikutnya untuk YouTube Music, ⏮ ⏯ ⏭). Ganti lagu: membesar 4 detik lalu menciut; selama pointer di atas island, ganti lagu tidak menciutkannya.
- Hover dibaca dari posisi pointer (`xdotool`), bukan dari urutan event enter/leave eww: event itu juga muncul saat aplikasi lain meng-grab pointer dan bisa diproses tidak berurutan.

Scroll ke atas/bawah di atas island ringkas mengubah volume keluaran default sebesar ±5%. Perubahan ini sekaligus membuka bisu (unmute), dengan batas 0–100%.

### Layar penuh

- Layar penuh: selama window aktif dalam mode layar penuh (`_NET_WM_STATE_FULLSCREEN`) menutupi monitor island (monitor 0), kedua window island ditutup; hover, ganti lagu, alert, dan notifikasi tidak membukanya. Notifikasi tetap masuk riwayat dunst (tab Notifikasi). Keluar dari layar penuh atau pindah ke window lain mengembalikan pill ringkas. Dipantau oleh `scripts/fullscreen` lewat event `xprop -spy` (`_NET_ACTIVE_WINDOW` dan `_NET_WM_STATE` window aktif), tanpa polling; dijalankan `island.sh` di samping daemon (bukan `deflisten`, karena eww menghentikan listener saat window-nya ditutup) dan berhenti bersama daemon. `ISLAND_FULLSCREEN_HIDE=0` saat menjalankan `island.sh` mematikannya.

## Tab

- Tab: kartu yang membesar punya tab **Musik** (kartu media), **Kalender** (agenda hari ini dan besok), **Cuaca** (kartu cuaca), **Notifikasi** (pusat notifikasi, lihat di bawah), **Tugas** (daftar tugas, lihat di bawah), dan **Pintasan** (tombol pintasan, lihat di bawah). Tab hanya tersedia selama ada isinya: Musik selama ada player yang memutar atau dijeda, Kalender selama data kalender tersedia, Cuaca selama cuaca tersedia, Notifikasi selama riwayat dunst berisi notifikasi, Pintasan selama `eww/shortcuts` berisi minimal satu pintasan; Tugas selalu tersedia. Jika lebih dari satu tab tersedia, baris tab kecil tampil di atas kartu: tab aktif tebal di atas chip abu gelap, tab lain redup. Klik tab untuk memilihnya; scroll ke atas/bawah di atas baris tab berpindah ke tab sebelumnya/berikutnya (memutar, satu perpindahan per 0,5 detik agar satu gerakan touchpad tidak melompati beberapa tab). Hover membuka tab yang terakhir dipilih, atau tab pertama yang tersedia bila tab itu kosong. Ganti lagu selalu membuka tab Musik tanpa mengubah pilihan tersimpan; saat musik berhenti, kartu yang tetap terbuka pindah ke Cuaca.

## Musik

Prioritas player diatur di `eww/players`, lihat [Konfigurasi → Player](konfigurasi.md#player).

- Ganti lagu: player sempat tidak melaporkan lagu sesaat. Selama itu pill tetap dalam mode musik dan kartu tetap di tab Musik, dengan kerangka abu-abu (cover, judul, artis, lirik, progress) tanpa teks sampai metadata lagu baru tiba. Musik baru dianggap berhenti (island menciut, tab beralih ke Cuaca) bila tidak ada lagu selama 1,5 detik (`ISLAND_MEDIA_GRACE`, detik; `0` = langsung).
- Saat membesar, judul lebih dari 30 karakter dan artis lebih dari 36 karakter bergulir sekitar 5 karakter/detik, dengan jeda 1,2 detik di awal tiap putaran dan pemisah `   ·   `. Teks pendek tetap diam; guliran dimulai ulang saat window dibuka atau lagu berganti, tanpa polling saat menciut.
- YouTube Music: selama player yang tampil adalah `ytm_player`, kontrol diapit tombol tidak suka (kiri) dan suka (kanan). Status suka lagu dibaca sekali per lagu di latar belakang lewat ytmusicapi (`get_watch_playlist`, sekitar 1,5 detik) dan disimpan selama listener berjalan; jawaban lambat untuk lagu sebelumnya diabaikan. Tombol yang aktif terisi dan berwarna aksen. Klik menjalankan `ytm like`/`ytm dislike`, atau `ytm unlike` bila status itu sudah aktif, lalu tampilan langsung berubah. Listener mengikuti state `scripts/media` lewat `inotifywait`, tanpa polling; `ytm status` dipanggil sekali saat lagu berganti untuk mengambil video ID.
- Lagu berikutnya: selama tombol suka tampil, di bawah progress ada satu baris redup `Berikutnya: judul — artis`, dipotong dengan elipsis bila melebihi lebar kartu. Antrean dibaca sekali per lagu dengan `ytm queue` (hanya baca) di latar belakang setelah video ID didapat; jawaban untuk lagu sebelumnya diabaikan dan baris lama langsung hilang saat lagu berganti. Lagu berikutnya dipilih seperti ytm-player sendiri: entri sesudah `current_index`, lagu yang sama saat repeat one, entri pertama saat repeat all tanpa shuffle di akhir antrean. Baris tidak tampil bila lagu yang diputar adalah entri terakhir (termasuk akhir antrean shuffle, karena urutan diacak ulang), tidak berada di posisi `current_index`, atau antrean gagal dibaca. Perubahan antrean tanpa ganti lagu baru terlihat pada lagu berikutnya.
- Headphone: selama output default adalah headset Bluetooth (sink `bluez_*`) atau port headphone/headset kabel, ikon headphone tampil di samping visualizer pada pill musik (ikon Bluetooth atau kabel; merah bila baterai ≤ 20%). Di tab Musik, baris di atas kontrol menampilkan nama perangkat dan baterai (`ULT WEAR · 90%`, hanya nama bila baterai tidak terbaca) rata kanan, berbagi baris dengan `Berikutnya: …`. Speaker dan HDMI tidak menampilkan apa pun. Listener `status` membaca ulang saat event sink/server `pactl subscribe` dan sinyal BlueZ `Connected`/`Battery1.Percentage` (`gdbus monitor`), tanpa polling; nama dan baterai dari `bluetoothctl info`.

Tombol suka/tidak suka dan lagu berikutnya memerlukan ytm-player yang sudah login, lihat [Konfigurasi → Tombol suka YouTube Music](konfigurasi.md#tombol-suka-youtube-music).

### Visualizer

- Visualizer hanya mengambil stream keluaran milik PID player MPRIS aktif atau proses turunannya, bukan mikrofon, monitor audio sistem, atau sumber audio default sebagai fallback. Metadata dan kontrol MPRIS tetap bekerja jika visualizer tidak mendapat audio.
- Audio visualizer hanya lewat memori/FIFO lokal, tidak disimpan atau diunggah. Unduhan cover tetap menggunakan jaringan.

### Lirik

- Lirik tersinkron dari LRCLIB, dengan NetEase Cloud Music sebagai fallback, tampil miring dan rata tengah pada kedua ukuran island. Untuk `ytm_player`, lirik YouTube Music dicoba lebih dulu (lihat [Lirik YouTube Music](#lirik-youtube-music)). Baris panjang dipotong dengan elipsis, tanpa bergulir atau mengecilkan font; tooltip menampilkan teks lengkap. Posisi MPRIS dibaca setiap 250 ms saat player aktif; listener hanya mengirim perubahan teks/status sinkron, bukan frame berulang. Saat belum ada baris lirik, intro, instrumental, hasil tidak tersedia, atau lookup gagal/timeout tanpa cache positif, judul dan artis asli tampil dengan warna redup.
- LRCLIB tidak memerlukan API key. Pencarian mengirim metadata judul, artis, dan durasi, bukan audio. Cache hasil positif berlaku 30 hari; hasil positif kedaluwarsa masih dipakai jika layanan gagal diakses. Cache negatif berlaku 24 jam hanya jika semua sumber yang dicoba memastikan tidak ada lirik tersinkron; cache negatif yang dibuat tanpa YouTube Music tidak berlaku untuk `ytm_player`. Error jaringan/timeout tidak disimpan sebagai hasil negatif.

### Lirik YouTube Music

Saat player aktif adalah `ytm_player`, listener mengambil video id dari `ytm status` (MPRIS ytm-player tidak membawanya), lalu meminta lirik lewat `ytmusicapi` dengan login ytm-player (`${XDG_CONFIG_HOME:-$HOME/.config}/ytm-player/auth.json`). Lookup berjalan di thread terpisah sehingga pembacaan posisi 250 ms tidak tertahan. Jika `ytmusicapi` tidak terpasang atau `auth.json` tidak ada, sumber ini dilewati tanpa pesan dan LRCLIB/NetEase tetap dipakai.

Urutan prioritas: lirik YouTube Music bertimestamp, lalu lirik tersinkron LRCLIB, NetEase, kemudian lirik YouTube Music biasa (tanpa timestamp), dan terakhir judul/artis. Permintaan bertimestamp yang gagal (misalnya HTTP 400) diulang tanpa timestamp; pada akun yang diuji, YouTube Music hanya memberi lirik biasa.

Lirik biasa tidak tersinkron: baris yang tampil hanya **perkiraan**, yaitu baris lirik dibagi rata sepanjang durasi lagu menurut posisi putar, sehingga bisa mendahului atau tertinggal dari lagu. Baris perkiraan ini tampil dengan warna redup seperti fallback, bukan gaya lirik tersinkron. Lirik biasa disimpan bersama cache negatif selama 24 jam agar sumber tersinkron dicek ulang setelahnya. Kegagalan `ytm status` atau request YouTube Music dianggap gangguan sementara dan mengikuti jadwal retry yang sama.

### Fallback lirik NetEase

Listener mencoba NetEase Cloud Music jika LRCLIB tidak menghasilkan lirik tersinkron yang cocok, termasuk saat LRCLIB gagal sementara. Endpoint NetEase ini tidak resmi dan dapat berubah atau berhenti tersedia. Listener mengirim judul dan artis ke server NetEase untuk pencarian, lalu membandingkan durasi dari hasilnya dengan durasi lagu aktif secara lokal. Audio tidak dikirim; akses tidak memakai login atau cookie.

Judul harus sama setelah normalisasi, termasuk penghapusan akhiran promosi. Jika salah satu nama artis atau alias cocok setelah normalisasi, toleransi durasinya ±2 detik. Jika artis tidak cocok, misalnya karena perbedaan aksara, hasil hanya diterima bila tepat satu kandidat memiliki judul sama dan durasi dalam ±1 detik. Listener membuang baris kredit di awal isi baris, tetapi mempertahankan timestamp lirik. Hasil instrumental, tanpa lirik, atau hanya kredit tidak ditampilkan sebagai lirik.

Lookup menunggu metadata stabil selama 1 detik; fallback judul/artis tetap berubah segera. Request kedua layanan berjarak minimal 200 ms dan memakai cooldown terpisah per host agar gangguan LRCLIB tidak menghalangi NetEase. Jika keduanya belum memberi hasil dan salah satunya gagal sementara, listener menjadwalkan maksimal tiga retry dengan jeda minimum 15, 30, lalu 60 detik, mengikuti `Retry-After` bila lebih lama.

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

## Notifikasi

Notifikasi dunst tampil di pill ringkas menggantikan isi idle atau media (musik tetap berjalan): ikon aplikasi (gambar dari path ikon notifikasi, selain itu ikon lonceng), ringkasan tebal, dan satu baris isi yang dipotong dengan elipsis. Markup dibuang dan entitas HTML diubah menjadi teks biasa. Tiap notifikasi bertahan 4 detik (`ISLAND_NOTIFY_SECONDS`), lalu tampilan sebelumnya kembali. Notifikasi berikutnya antre dan tampil bergantian; jika lebih dari tiga menunggu, sisanya digabung menjadi satu entri `+N notifikasi` di akhir antrean. Pembaruan dengan ID yang sama, atau notifikasi dari aplikasi dengan stack tag yang sama, menggantikan entri lama di tempatnya. Alert selalu didahulukan: notifikasi yang sedang tampil berhenti menghitung selama alert tampil lalu melanjutkan sisa waktunya, dan notifikasi baru menunggu sampai alert hilang. Selama island membesar, notifikasi ditunda dengan cara yang sama sampai island menciut; hover di atas notifikasi tidak membesarkan island. Saat Jangan Ganggu dunst aktif, notifikasi tidak tampil di island.

Semua notifikasi, termasuk yang kritis, hanya tampil di island (tanpa popup dunst); notifikasi kritis diberi aksen merah. Klik pada notifikasi menutupnya dari island dan membuka aplikasinya: window aplikasi yang terlihat diaktifkan dengan `xdotool`, dicari lewat `StartupWMClass` desktop entry, ID desktop entry, lalu nama aplikasi; jika tidak ada window dan notifikasi membawa desktop entry, aplikasi dijalankan dengan `gtk-launch`. Klik pada `+N notifikasi` hanya menutupnya.

Cara launcher menyembunyikan popup dunst dijelaskan di [Konfigurasi → Integrasi dunst](konfigurasi.md#integrasi-dunst).

### Tab Notifikasi

Tab **Notifikasi** di kartu yang membesar adalah pusat notifikasi ala NotchNook. Isinya riwayat dunst (`dunstctl history`): karena popup disembunyikan, dunst menyimpan setiap notifikasi di sana beserta ID-nya, riwayat itu tetap ada saat island dijalankan ulang, dan `history-rm`/`history-clear` langsung bekerja padanya. Kegagalan launcher (`eww-island`) dan OSD volume/kecerahan tidak ikut; salinan lama dengan ID yang sama atau aplikasi dan stack tag yang sama (misalnya progres unduhan) diwakili salinan terbaru. Maksimal 4 baris tampil, terbaru di atas: ikon (gambar dari path ikon, selain itu lonceng), ringkasan tebal dan waktu relatif (`baru saja`, `5 mnt`, `2 jam`, `3 hari`), lalu satu baris isi redup dan nama aplikasi di kanan. Scroll di atas daftar menggeser ke notifikasi yang lebih lama; `+N lainnya` menghitung sisanya. Klik baris membuka aplikasinya seperti klik pada pill (desktop entry diingat dari `notify-hook`, karena riwayat dunst tidak menyimpannya) lalu menghapusnya dari riwayat; **Hapus semua** mengosongkan riwayat. Label tab menampilkan jumlah notifikasi yang belum dibaca, misalnya `Notifikasi 3`: notifikasi yang datang setelah tab terakhir dilihat. Listener `scripts/notif` membaca riwayat hanya saat ada notifikasi baru, klik, hapus, atau island dibuka; selama kartu terbuka waktu relatif diperbarui tiap menit.

## Indikator

Indikator tampil pada pill idle dan media: titik merah dengan durasi berarti layar sedang direkam, titik kuning berarti mikrofon dipakai, titik hijau berarti kamera dipakai, dan ikon lonceng dicoret berarti Jangan Ganggu dunst aktif. Tooltip mikrofon dan kamera mencantumkan aplikasi yang memakainya. Deteksi kamera hanya melihat proses milik pengguna yang sama.

Perekaman layar terdeteksi dari proses milik pengguna yang sama: `ffmpeg` dengan format input `-f x11grab` atau `-f kmsgrab`, atau OBS (`obs` maupun helper `obs-ffmpeg-mux`) yang sedang menulis berkas `.mkv`/`.mp4`/`.mov`/`.flv`/`.ts`/`.webm`. Saat tidak merekam, `/proc` diperiksa setiap 2 detik (`ISLAND_REC_INTERVAL`); selama merekam, durasi sejak rekaman pertama terdeteksi diperbarui setiap detik dan tooltip menyebut aplikasinya.

## Cuaca

Cuaca berasal dari wttr.in. Pill idle menampilkan ikon, suhu, dan kota, rata tengah. Hover di atas island idle selama 0,3 detik membuka kartu detail 508×218 px: kondisi cuaca, suhu, kota dan wilayah, waktu matahari terbit/terbenam, suhu terasa, kelembapan, angin, indeks UV, serta prakiraan 3 hari dengan suhu maksimum/minimum dan peluang hujan. Jika cuaca tidak tersedia, hover idle membuka tab lain (paling tidak Tugas). Cuaca diperbarui setiap 30 menit, dicoba ulang setelah 5 menit jika gagal, dan cache dapat dipakai selama 3 jam. Listener yang dimulai ulang (misalnya island kembali setelah layar penuh) memakai cache yang berumur kurang dari 30 menit tanpa mengambil ulang.

Warna ikon cuaca (pill, kartu, dan prakiraan) mengikuti kondisi lalu suhu: hujan biru, badai magenta, salju putih, kabut dan berawan abu; selain itu ≥33° merah (panas), ≤15° cyan (dingin), cerah malam biru pucat, ≥28° jingga (hangat), cerah kuning. Prakiraan memakai suhu maksimum dan selalu dianggap siang. Warna berasal dari palet tema bar.

Urutan lokasi, GeoClue, dan privasi: [Konfigurasi → Lokasi cuaca](konfigurasi.md#lokasi-cuaca).

## Tugas

Tab **Tugas** adalah daftar tugas singkat yang selalu tersedia (agar tugas pertama bisa ditambahkan), sehingga hover selalu membuka kartu; label tab memuat jumlah tugas yang belum selesai (`Tugas 3`). Daftar disimpan di `${XDG_DATA_HOME:-$HOME/.local/share}/eww-island/todo.json` sehingga tetap ada setelah reboot; perubahan ditulis atomik di bawah `flock`, dan file rusak dibaca sebagai daftar kosong lalu disisihkan sebagai `todo.json.corrupt` saat perubahan berikutnya. Urutan: tugas terbuka terbaru di atas, lalu tugas selesai (dicoret dan redup) yang terakhir diselesaikan di atas. Maksimal 4 baris tampil; scroll di atas daftar menggeser baris, `+N lainnya` menghitung sisanya. Kotak centang menandai selesai/belum, `×` menghapus, **Bersihkan selesai** menghapus semua tugas selesai. Kartu island tidak bisa menerima fokus keyboard di Openbox (window override-redirect), jadi **+ Tambah** menutup kartu lalu meminta teks lewat `rofi -dmenu -p Tugas`; teks dirapikan menjadi satu baris (maksimal 200 karakter) dan teks kosong diabaikan. Dari terminal: `scripts/todo add TEKS | toggle ID | remove ID | clear-done`.

### Deadline

Deadline bersifat opsional. Setelah **+ Tambah** meminta teks, rofi menawarkan **Tanpa deadline** sebagai pilihan pertama, lalu preset **Hari ini 17:00**, **Besok 09:00**, **Besok 17:00**, **Jumat 17:00**, dan **Senin 09:00**. Tombol **󰃰** di setiap baris membuka pengaturan deadline, termasuk **Hapus deadline**. Bisa juga mengetik `hari ini`, `besok`, `lusa`, nama hari `senin`–`minggu`, `28 okt`, atau `28/10`, dengan waktu opsional seperti `17:00`, `17.00`, `jam 17`, atau `jam 17:30`; tanggal tanpa waktu memakai pukul 17:00 secara bawaan.

Chip deadline tampil di samping teks: redup untuk deadline yang masih jauh (misalnya `Jum 17:00`), kuning jika kurang dari 24 jam (misalnya `besok 09:00`), dan merah dengan label `terlambat` jika sudah lewat. Tugas tanpa deadline tidak menampilkan chip. Dari terminal: `scripts/todo add TEKS --due EPOCH`, `scripts/todo set-due ID EPOCH|none`, atau `scripts/todo due ID` untuk membuka rofi.

Pengingat H-1 dan hari H dikirim pukul 09:00 secara bawaan sebagai notifikasi aplikasi **Tugas**, dengan judul `Deadline besok · HH:MM` atau `Deadline hari ini · HH:MM`; notifikasinya tetap tersimpan di tab **Notifikasi**. Jika beberapa pengingat terlewat, hanya yang terbaru dikirim. Tugas selesai tidak diingatkan; mengubah deadline mengaktifkan ulang pengingat. Waktu dan interval dapat diatur lewat [variabel lingkungan](konfigurasi.md#variabel-lingkungan).

## Kalender

Tab **Kalender** menampilkan jadwal hari ini dan besok dari beberapa kalender iCal, dengan titik warna per akun. Empat baris tampil sekaligus; posisi awal dimulai dari acara pertama yang belum berakhir. Scroll ke atas untuk melihat acara sebelumnya atau ke bawah untuk melihat sisanya. Acara yang sudah lewat redup, acara berlangsung disorot, dan waktu acara yang segera dimulai berwarna kuning. Acara seharian diringkas dalam satu baris. Acara yang ditolak disembunyikan jika EMAIL akun diisi.

### Menyiapkan kalender

1. Pasang paket Arch: `sudo pacman -S --needed python-icalendar python-recurring-ical-events`.
2. Untuk setiap kalender Google, buka Settings → pilih kalender → Integrate calendar → salin **Secret address in iCal format**.
3. Buat direktori `~/.config/openbox-island`, lalu berkas `~/.config/openbox-island/calendars` dengan satu akun per baris:

   ```text
   # NAME | #RRGGBB | EMAIL | URL
   Kantor | #4f8cff | nama@example.com | https://calendar.google.com/calendar/ical/ALAMAT-RAHASIA/basic.ics
   Pribadi | #34c759 | | https://calendar.google.com/calendar/ical/ALAMAT-RAHASIA-LAIN/basic.ics
   ```

   Ganti URL contoh dengan alamat rahasia kalender masing-masing. EMAIL boleh kosong; baris berawalan `#` adalah komentar.
4. Batasi akses: `chmod 600 ~/.config/openbox-island/calendars`.
5. Jalankan `~/.config/eww-island/scripts/agenda check`. Setiap akun menampilkan `NAME: OK, …` atau error, tanpa mencetak URL. Jalankan ulang island setelah konfigurasi siap.

Tombol **Join** tersedia pada acara yang memiliki tautan rapat dan belum berakhir. Klik menutup kartu lebih dulu, lalu membuka tautan. Data diambil ulang setiap 300 detik; tab membaca data lokal setiap 2 detik. Saat offline, feed cache tetap dipakai dengan catatan `diperbarui HH:MM`.

Pengingat dikirim sebagai notifikasi aplikasi **Kalender** 10 menit sebelum rapat (`Meeting 10 menit lagi · HH:MM`) dan saat mulai (`Meeting dimulai · HH:MM`), lalu kartu membuka tab Kalender selama 10 detik. Atur waktunya lewat [variabel lingkungan](konfigurasi.md#variabel-lingkungan); `ISLAND_MEETING_BEFORE` kosong mematikan pengingat sebelum rapat.

Alamat iCal rahasia adalah kata sandi: siapa pun yang memilikinya dapat membaca kalender. Simpan hanya di berkas konfigurasi di luar repo, jangan masukkan ke commit atau screenshot. Cache kalender tersimpan di `~/.cache/eww-island/calendar`.

## Pintasan

Tab **Pintasan** berisi tombol ikon berlabel, tiga per baris, dibaca dari `eww/shortcuts` (perubahan langsung terbaca lewat `inotifywait`). Satu baris per tombol: `IKON | LABEL | PERINTAH`, opsional `| dnd` agar tombol menyala selama Jangan Ganggu dunst aktif; baris kosong dan baris berawalan `#` diabaikan, baris rusak dilewati dengan peringatan di log. Bawaan: Screenshot (`ob-screenshot --area`), Color picker (`ob-colorpicker`), Kunci layar (`betterlockscreen --lock`), Jangan ganggu (`dunstctl set-paused toggle`), Bluetooth (`rofi-bluetooth`), Daya (`rofi-powermenu`). Klik menutup kartu lebih dulu (agar tidak ikut tertangkap screenshot atau color picker), lalu menjalankan perintah lewat `sh` di sesi sendiri (`setsid`) tanpa output ke eww. Jika programnya tidak ditemukan, muncul notifikasi "Perintah tidak ditemukan". Karena tab ini selalu ada, hover di atas pill idle kini selalu membuka kartu; Musik, Cuaca, dan Notifikasi tetap didahulukan bila belum ada tab tersimpan.
